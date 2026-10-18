# Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license
"""
Topology-Shape-aware VMamba (TS-VMamba) Module.

A research-oriented neural architecture combining 2D Selective State Space Models (SS2D/VMamba)
for long-range global spatial dependencies with Multi-Scale Shape & Directional Topological
Awareness for precise boundary, contour, and structural representation in medical image segmentation.
"""

from __future__ import annotations

import math
import torch
import torch.nn as nn
import torch.nn.functional as F

from .conv import Conv


def parallel_associative_scan(a: torch.Tensor, b: torch.Tensor) -> torch.Tensor:
    """Vectorized parallel associative scan for linear recurrence h_t = a_t * h_{t-1} + b_t.

    Computes the prefix scan in O(log L) parallel steps using standard tensor slicing.
    Zero token-wise Python loops, fully differentiable, and AMP-compatible.

    Args:
        a (torch.Tensor): Transition decay matrix of shape (..., L), with values in (0, 1].
        b (torch.Tensor): Driving term of shape (..., L).

    Returns:
        torch.Tensor: Hidden states h of shape (..., L).
    """
    L = a.size(-1)
    if L <= 1:
        return b

    num_steps = (L - 1).bit_length()
    pad_len = (1 << num_steps) - L
    if pad_len > 0:
        a = F.pad(a, (0, pad_len), value=1.0)
        b = F.pad(b, (0, pad_len), value=0.0)

    total_len = 1 << num_steps
    step = 1
    while step < total_len:
        a_left = a[..., :-step]
        b_left = b[..., :-step]
        a_right = a[..., step:]
        b_right = b[..., step:]

        a = torch.cat([a[..., :step], a_right * a_left], dim=-1)
        b = torch.cat([b[..., :step], a_right * b_left + b_right], dim=-1)
        step *= 2

    return b[..., :L]


class SS2D(nn.Module):
    """2D Selective Scan Module (SS2D) for VMamba.

    Processes 2D spatial feature maps via 4-directional selective state-space scanning
    (raster forward, raster backward, transpose forward, transpose backward) with
    fully vectorized parallel prefix scan and dynamic discretization parameters.

    Attributes:
        d_model (int): Input feature channel dimension.
        d_state (int): State-space hidden dimension (N).
        d_conv (int): 2D depthwise convolution kernel size.
        expand (float): Channel expansion factor.
        dt_rank (int): Rank for delta step-size projection.
    """

    def __init__(
        self,
        d_model: int,
        d_state: int = 16,
        d_conv: int = 3,
        expand: float = 1.0,
        dt_rank: int | None = None,
        bias: bool = False,
    ):
        """Initialize SS2D module.

        Args:
            d_model (int): Number of input channels.
            d_state (int): SSM state dimension.
            d_conv (int): Depthwise convolution kernel size.
            expand (float): Expansion factor for inner dimension.
            dt_rank (int | None): Rank of delta projection.
            bias (bool): Whether to include bias in linear projections.
        """
        super().__init__()
        self.d_model = d_model
        self.d_state = d_state
        self.d_conv = d_conv
        self.expand = expand
        self.d_inner = int(self.expand * self.d_model)
        self.dt_rank = math.ceil(self.d_model / 16) if dt_rank is None else dt_rank

        # In-projection splits into (u, z)
        self.in_proj = nn.Conv2d(self.d_model, self.d_inner * 2, kernel_size=1, bias=bias)

        # 2D Spatial Depthwise Convolution
        self.conv2d = nn.Conv2d(
            in_channels=self.d_inner,
            out_channels=self.d_inner,
            groups=self.d_inner,
            kernel_size=d_conv,
            padding=(d_conv - 1) // 2,
            bias=bias,
        )
        self.act = nn.SiLU(inplace=False)

        # SSM parameter projections for 4 scan directions
        # Each direction projects d_inner -> (dt_rank + 2 * d_state)
        self.x_proj = nn.ModuleList(
            [nn.Linear(self.d_inner, self.dt_rank + self.d_state * 2, bias=False) for _ in range(4)]
        )

        self.dt_projs = nn.ModuleList(
            [nn.Linear(self.dt_rank, self.d_inner, bias=True) for _ in range(4)]
        )

        # Initialize A parameter for 4 directions: log-space positive values -> A = -exp(A_logs)
        A = torch.arange(1, self.d_state + 1, dtype=torch.float32).repeat(self.d_inner, 1)
        self.A_logs = nn.Parameter(torch.stack([torch.log(A) for _ in range(4)], dim=0))  # (4, d_inner, d_state)

        # Output projection
        self.out_proj = nn.Conv2d(self.d_inner, self.d_model, kernel_size=1, bias=bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Forward pass through SS2D.

        Args:
            x (torch.Tensor): Input tensor of shape (B, C, H, W).

        Returns:
            torch.Tensor: Output tensor of shape (B, C, H, W).
        """
        B, C, H, W = x.shape
        L = H * W

        # Linear projection to (u, z)
        xz = self.in_proj(x)
        u, z = xz.chunk(2, dim=1)  # (B, D, H, W) each

        # 2D Depthwise Conv + Activation (out-of-place)
        u = F.silu(self.conv2d(u), inplace=False)  # (B, D, H, W)

        # Create 4 scanning sequences
        # Dir 0: Raster forward (row-major)
        u_0 = u.flatten(2)  # (B, D, L)
        # Dir 1: Raster backward (flipped)
        u_1 = u_0.flip(-1)  # (B, D, L)
        # Dir 2: Column-major forward (transposed)
        u_2 = u.transpose(2, 3).flatten(2)  # (B, D, L)
        # Dir 3: Column-major backward (transposed flipped)
        u_3 = u_2.flip(-1)  # (B, D, L)

        us = [u_0, u_1, u_2, u_3]
        ys = []

        for k in range(4):
            u_k = us[k]  # (B, D, L)
            u_k_perm = u_k.transpose(1, 2)  # (B, L, D)

            # Project to dt, B, C
            proj = self.x_proj[k](u_k_perm)  # (B, L, dt_rank + 2 * d_state)
            dt_raw, B_raw, C_raw = torch.split(proj, [self.dt_rank, self.d_state, self.d_state], dim=-1)

            dt = self.dt_projs[k](dt_raw).transpose(1, 2)  # (B, D, L)
            dt = F.softplus(dt)  # (B, D, L), positive step sizes

            B_mat = B_raw.transpose(1, 2)  # (B, N, L)
            C_mat = C_raw.transpose(1, 2)  # (B, N, L)

            # Continuous -> Discrete SSM parameters
            # A_logs: (D, N) -> A: (D, N), negative
            A = -torch.exp(self.A_logs[k])
            # delta * A: (B, D, N, L)
            delta_A = dt.unsqueeze(2) * A.unsqueeze(0).unsqueeze(-1)
            # Bound delta_A to prevent extreme negative underflow
            delta_A = torch.clamp(delta_A, min=-50.0, max=0.0)
            a_mat = torch.exp(delta_A)  # (B, D, N, L) in (0, 1]

            # Driving input: delta * B * u -> (B, D, N, L)
            b_mat = dt.unsqueeze(2) * B_mat.unsqueeze(1) * u_k.unsqueeze(2)

            # Parallel associative scan across L
            h = parallel_associative_scan(a_mat, b_mat)  # (B, D, N, L)

            # State to output projection: y = sum_n (C_n * h_n)
            y_k = torch.einsum("bdnl,bnl->bdl", h, C_mat)  # (B, D, L)
            ys.append(y_k)

        # Reshape and fold 4 directions back to spatial grid (B, D, H, W)
        y_0 = ys[0].view(B, self.d_inner, H, W)
        y_1 = ys[1].flip(-1).view(B, self.d_inner, H, W)
        y_2 = ys[2].view(B, self.d_inner, W, H).transpose(2, 3)
        y_3 = ys[3].flip(-1).view(B, self.d_inner, W, H).transpose(2, 3)

        # Aggregate 4 directions
        y = y_0 + y_1 + y_2 + y_3

        # Gated modulation by z (out-of-place)
        y = y * F.silu(z, inplace=False)

        # Out projection
        out = self.out_proj(y)
        return out


class ShapeAwareBranch(nn.Module):
    """Multi-Scale Geometric Shape Representation Branch.

    Extracts multi-scale local contour, curvature, and boundary cues via
    parallel depthwise convolutions with complementary receptive fields (3x3 and 5x5).
    """

    def __init__(self, c1: int, c2: int):
        """Initialize ShapeAwareBranch.

        Args:
            c1 (int): Input channel dimension.
            c2 (int): Output channel dimension.
        """
        super().__init__()
        self.dw3 = Conv(c1, c1, k=3, s=1, p=1, g=c1, act=True)
        self.dw5 = Conv(c1, c1, k=5, s=1, p=2, g=c1, act=True)
        self.fuse = Conv(2 * c1, c2, k=1, s=1, act=True)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Forward pass extracting geometric shape features.

        Args:
            x (torch.Tensor): Input tensor of shape (B, C, H, W).

        Returns:
            torch.Tensor: Geometric shape feature map of shape (B, C, H, W).
        """
        s3 = self.dw3(x)
        s5 = self.dw5(x)
        return self.fuse(torch.cat([s3, s5], dim=1))


class DirectionalShapeExtractor(nn.Module):
    """Differentiable Structural & Topological Directional Feature Extractor.

    Extracts horizontal continuity (1x5), vertical continuity (5x1), local omnidirectional
    curvature (3x3), and continuous boundary gradient magnitude to capture topological
    connectedness of polyp contours.
    """

    def __init__(self, c: int):
        """Initialize DirectionalShapeExtractor.

        Args:
            c (int): Feature channel dimension.
        """
        super().__init__()
        # Horizontal response (1x5 strip kernel for horizontal continuity)
        self.h_conv = Conv(c, c, k=(1, 5), s=1, p=(0, 2), g=c, act=True)
        # Vertical response (5x1 strip kernel for vertical continuity)
        self.v_conv = Conv(c, c, k=(5, 1), s=1, p=(2, 0), g=c, act=True)
        # Local omnidirectional curvature response (3x3)
        self.local_conv = Conv(c, c, k=3, s=1, p=1, g=c, act=True)
        # Directional fusion
        self.topo_fuse = Conv(4 * c, c, k=1, s=1, act=True)
        # Unified Topology-Shape aggregation
        self.unify = Conv(2 * c, c, k=1, s=1, act=True)

    def forward(self, s_shape: torch.Tensor) -> torch.Tensor:
        """Forward pass extracting directional and topological structural features.

        Args:
            s_shape (torch.Tensor): Geometric shape feature map (B, C, H, W).

        Returns:
            torch.Tensor: Topology-Shape structural representation (B, C, H, W).
        """
        s_h = self.h_conv(s_shape)
        s_v = self.v_conv(s_shape)
        s_loc = self.local_conv(s_shape)

        # Differentiable boundary gradient magnitude: sqrt(s_h^2 + s_v^2 + eps)
        s_grad = torch.sqrt(s_h.pow(2) + s_v.pow(2) + 1e-6)

        # Fuse directional components
        s_topo = self.topo_fuse(torch.cat([s_h, s_v, s_loc, s_grad], dim=1))

        # Combine shape and topology features
        s_unified = self.unify(torch.cat([s_shape, s_topo], dim=1))
        return s_unified


class TopologyShapeGate(nn.Module):
    """Topology-Shape Guidance Gate.

    Generates a bounded continuous guidance map G_TS in [0, 1] to modulate VMamba features.
    """

    def __init__(self, c: int):
        """Initialize TopologyShapeGate.

        Args:
            c (int): Feature channel dimension.
        """
        super().__init__()
        self.gate_conv = nn.Sequential(
            nn.Conv2d(c, c, kernel_size=1, bias=True),
            nn.Sigmoid(),
        )

    def forward(self, s: torch.Tensor) -> torch.Tensor:
        """Generate guidance gate map.

        Args:
            s (torch.Tensor): Topology-Shape feature map (B, C, H, W).

        Returns:
            torch.Tensor: Guidance map G_TS with values in [0, 1] of shape (B, C, H, W).
        """
        return self.gate_conv(s)


class TSVMamba(nn.Module):
    """Topology-Shape-aware VMamba Block (TSVMamba).

    Integrates VMamba (SS2D) for global spatial context with ShapeAwareBranch and
    DirectionalShapeExtractor for local geometric and topological contour representation.
    The Topology-Shape guidance map G_TS modulates the VMamba feature representation:
        F_M' = F_M ⊙ (1 + G_TS)
    followed by 1x1 fusion, feed-forward refinement, and a stabilized residual connection.

    Supports multiple ablation modes:
        - 'topology_shape_vmamba': Full proposed model with guidance modulation.
        - 'vmamba_only': VMamba (SS2D) global context only.
        - 'shape_only': Shape & Directional branch only.
        - 'shape_vmamba_no_guidance': VMamba and Shape fused directly without guidance.
    """

    def __init__(
        self,
        c: int,
        d_state: int = 16,
        d_conv: int = 3,
        expand: float = 1.0,
        mode: str = "topology_shape_vmamba",
    ):
        """Initialize TSVMamba block.

        Args:
            c (int): Number of input/output channels.
            d_state (int): SSM hidden state dimension.
            d_conv (int): 2D depthwise convolution kernel size.
            expand (float): VMamba inner expansion factor.
            mode (str): Architecture ablation mode.
        """
        super().__init__()
        self.c = c
        self.mode = mode

        # 1. Global VMamba Branch
        if self.mode in ("topology_shape_vmamba", "vmamba_only", "shape_vmamba_no_guidance"):
            self.vmamba = SS2D(d_model=c, d_state=d_state, d_conv=d_conv, expand=expand)

        # 2. Local Geometric Shape & Directional Topology Branch
        if self.mode in ("topology_shape_vmamba", "shape_only", "shape_vmamba_no_guidance"):
            self.shape_branch = ShapeAwareBranch(c, c)
            self.directional_extractor = DirectionalShapeExtractor(c)

        # 3. Topology-Shape Guidance Gate
        if self.mode == "topology_shape_vmamba":
            self.gate = TopologyShapeGate(c)

        # 4. Fusion Layer
        if self.mode in ("topology_shape_vmamba", "shape_vmamba_no_guidance"):
            self.fuse = Conv(2 * c, c, k=1, s=1, act=True)

        # 5. Feed-Forward Refinement (FFN)
        self.ffn = nn.Sequential(
            Conv(c, 2 * c, k=1, s=1, act=True),
            Conv(2 * c, c, k=1, s=1, act=False),
        )

        # 6. Learnable Residual Scaling Parameter (initialized to 1e-3 for training stability)
        self.gamma = nn.Parameter(torch.full((1,), 0.001, dtype=torch.float32))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Forward pass through TSVMamba block.

        Args:
            x (torch.Tensor): Input tensor of shape (B, C, H, W).

        Returns:
            torch.Tensor: Output tensor of shape (B, C, H, W).
        """
        if self.mode == "topology_shape_vmamba":
            # Global VMamba feature
            f_m = self.vmamba(x)
            # Local multi-scale geometric shape and directional topology feature
            s_shape = self.shape_branch(x)
            s = self.directional_extractor(s_shape)
            # Topology-Shape guidance map
            g_ts = self.gate(s)
            # Shape-aware VMamba feature modulation
            f_m_mod = f_m * (1.0 + g_ts)
            # 1x1 Fusion
            f_fused = self.fuse(torch.cat([f_m_mod, s], dim=1))
            # FFN refinement
            f_out = self.ffn(f_fused)
            # Residual connection
            return x + self.gamma * f_out

        elif self.mode == "vmamba_only":
            f_m = self.vmamba(x)
            f_out = self.ffn(f_m)
            return x + self.gamma * f_out

        elif self.mode == "shape_only":
            s_shape = self.shape_branch(x)
            s = self.directional_extractor(s_shape)
            f_out = self.ffn(s)
            return x + self.gamma * f_out

        elif self.mode == "shape_vmamba_no_guidance":
            f_m = self.vmamba(x)
            s_shape = self.shape_branch(x)
            s = self.directional_extractor(s_shape)
            f_fused = self.fuse(torch.cat([f_m, s], dim=1))
            f_out = self.ffn(f_fused)
            return x + self.gamma * f_out

        else:
            raise ValueError(f"Unsupported TSVMamba mode: '{self.mode}'")


class C2TSVMamba(nn.Module):
    """C2 wrapper for Topology-Shape-aware VMamba (C2TSVMamba).

    Follows the standard Ultralytics C2/C2PSA split-transform-concatenate design pattern:
        x -> cv1 -> split(a, b) -> TSVMamba(b) -> concat(a, b') -> cv2 -> y
    Seamlessly integrates into YOLO architectures as a direct replacement for C2PSA or C3k2.

    Attributes:
        c (int): Hidden channel dimension.
        cv1 (Conv): 1x1 convolution reducing input channels to 2*c.
        cv2 (Conv): 1x1 convolution projecting 2*c channels back to c1.
        m (nn.Sequential): Container of TSVMamba blocks.
    """

    def __init__(
        self,
        c1: int,
        c2: int,
        n: int = 1,
        e: float = 0.5,
        d_state: int = 16,
        d_conv: int = 3,
        mode: str = "topology_shape_vmamba",
    ):
        """Initialize C2TSVMamba module.

        Args:
            c1 (int): Input channel dimension.
            c2 (int): Output channel dimension.
            n (int): Number of TSVMamba blocks.
            e (float): Channel expansion/split ratio.
            d_state (int): SSM hidden state dimension.
            d_conv (int): 2D depthwise convolution kernel size.
            mode (str): TSVMamba ablation mode.
        """
        super().__init__()
        assert c1 == c2, f"C2TSVMamba requires c1 == c2, got c1={c1}, c2={c2}"
        self.c = int(c1 * e)
        self.cv1 = Conv(c1, 2 * self.c, 1, 1)
        self.cv2 = Conv(2 * self.c, c1, 1)
        self.m = nn.Sequential(
            *(
                TSVMamba(
                    c=self.c,
                    d_state=d_state,
                    d_conv=d_conv,
                    expand=1.0,
                    mode=mode,
                )
                for _ in range(n)
            )
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Forward pass through C2TSVMamba.

        Args:
            x (torch.Tensor): Input tensor of shape (B, C, H, W).

        Returns:
            torch.Tensor: Output tensor of shape (B, C, H, W).
        """
        a, b = self.cv1(x).split((self.c, self.c), dim=1)
        b = self.m(b)
        return self.cv2(torch.cat((a, b), dim=1))
