# Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license
"""VMambaBlock module with 4-directional selective scan for YOLO feature maps."""

import torch
import torch.nn as nn
import torch.nn.functional as F

from .transformer import LayerNorm2d

try:
    from mamba_ssm.ops.selective_scan_interface import selective_scan_fn

    HAS_MAMBA = True
except (ImportError, ModuleNotFoundError):
    HAS_MAMBA = False
    selective_scan_fn = None


def selective_scan_pytorch(
    u: torch.Tensor,
    delta: torch.Tensor,
    A: torch.Tensor,
    B: torch.Tensor,
    C: torch.Tensor,
    D: torch.Tensor | None = None,
    delta_bias: torch.Tensor | None = None,
    delta_softplus: bool = True,
) -> torch.Tensor:
    """Pure PyTorch fallback implementation of selective scan for a single direction."""
    dtype_orig = u.dtype
    u = u.to(torch.float32)
    delta = delta.to(torch.float32)
    A = A.to(torch.float32)
    B = B.to(torch.float32)
    C = C.to(torch.float32)
    if D is not None:
        D = D.to(torch.float32)
    if delta_bias is not None:
        delta = delta + delta_bias.to(torch.float32).unsqueeze(0).unsqueeze(-1)
    if delta_softplus:
        delta = F.softplus(delta)

    batch_size, dim, seq_len = u.shape
    dstate = A.shape[1]
    delta_A = torch.einsum("bdl,dn->bdnl", delta, A)
    deltaA_exp = torch.exp(delta_A)
    delta_B_u = torch.einsum("bdl,bnl,bdl->bdnl", delta, B, u)

    h = torch.zeros((batch_size, dim, dstate), device=u.device, dtype=torch.float32)
    ys = []
    for t in range(seq_len):
        h = deltaA_exp[:, :, :, t] * h + delta_B_u[:, :, :, t]
        y_t = torch.einsum("bdn,bn->bd", h, C[:, :, t])
        ys.append(y_t)

    y = torch.stack(ys, dim=2)
    if D is not None:
        y = y + u * D.unsqueeze(0).unsqueeze(-1)
    return y.to(dtype_orig)


class SS2D(nn.Module):
    """2D Selective Scan module with 4-directional cross-scan mechanism."""

    def __init__(self, d_model: int, d_state: int = 16, expand: int = 1):
        super().__init__()
        self.d_model = d_model
        self.d_state = d_state
        self.d_inner = int(d_model * expand)
        self.dt_rank = max(1, round(self.d_inner / 16))

        self.in_proj = nn.Conv2d(d_model, self.d_inner * 2, 1, bias=False)
        self.dwconv = nn.Conv2d(
            self.d_inner, self.d_inner, kernel_size=3, padding=1, groups=self.d_inner, bias=False
        )
        self.act = nn.SiLU(inplace=False)

        self.x_proj = nn.ModuleList(
            [
                nn.Linear(self.d_inner, self.dt_rank + self.d_state * 2, bias=False)
                for _ in range(4)
            ]
        )
        self.dt_proj = nn.ModuleList(
            [nn.Linear(self.dt_rank, self.d_inner, bias=True) for _ in range(4)]
        )
        self.A_logs = nn.ParameterList(
            [
                nn.Parameter(
                    torch.log(
                        torch.arange(1, d_state + 1, dtype=torch.float32)
                        .unsqueeze(0)
                        .repeat(self.d_inner, 1)
                    )
                )
                for _ in range(4)
            ]
        )
        self.Ds = nn.ParameterList(
            [nn.Parameter(torch.ones(self.d_inner, dtype=torch.float32)) for _ in range(4)]
        )
        self.out_proj = nn.Conv2d(self.d_inner, d_model, 1, bias=False)
        self.last_forward_used_fast_path = False

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        batch, _, h, w = x.shape
        xz = self.in_proj(x)
        x_branch, z_gate = xz.chunk(2, dim=1)
        x_branch = F.silu(self.dwconv(x_branch), inplace=False)

        x_1 = x_branch.flatten(2, 3)
        x_2 = torch.flip(x_1, dims=[-1])
        x_3 = x_branch.transpose(2, 3).flatten(2, 3)
        x_4 = torch.flip(x_3, dims=[-1])
        seqs = [x_1, x_2, x_3, x_4]
        ys = []
        fast_path_used = False

        if HAS_MAMBA and x.is_cuda and selective_scan_fn is not None:
            try:
                ys_fast = []
                for k in range(4):
                    u_k = seqs[k]
                    dbc = self.x_proj[k](u_k.transpose(1, 2))
                    dt, B_k, C_k = torch.split(
                        dbc, [self.dt_rank, self.d_state, self.d_state], dim=-1
                    )
                    delta = self.dt_proj[k].weight @ dt.transpose(1, 2)
                    delta_bias = self.dt_proj[k].bias
                    A_k = -torch.exp(self.A_logs[k].float())
                    B_k = B_k.transpose(1, 2).contiguous()
                    C_k = C_k.transpose(1, 2).contiguous()
                    D_k = self.Ds[k].float()
                    y_k = selective_scan_fn(
                        u_k,
                        delta,
                        A_k,
                        B_k,
                        C_k,
                        D=D_k,
                        delta_bias=delta_bias,
                        delta_softplus=True,
                    )
                    ys_fast.append(y_k)
                ys = ys_fast
                fast_path_used = True
            except Exception:
                fast_path_used = False

        if not fast_path_used:
            ys = []
            for k in range(4):
                u_k = seqs[k]
                dbc = self.x_proj[k](u_k.transpose(1, 2))
                dt, B_k, C_k = torch.split(
                    dbc, [self.dt_rank, self.d_state, self.d_state], dim=-1
                )
                delta = self.dt_proj[k].weight @ dt.transpose(1, 2)
                delta_bias = self.dt_proj[k].bias
                A_k = -torch.exp(self.A_logs[k].float())
                B_k = B_k.transpose(1, 2).contiguous()
                C_k = C_k.transpose(1, 2).contiguous()
                D_k = self.Ds[k].float()
                y_k = selective_scan_pytorch(
                    u_k,
                    delta,
                    A_k,
                    B_k,
                    C_k,
                    D=D_k,
                    delta_bias=delta_bias,
                    delta_softplus=True,
                )
                ys.append(y_k)

        self.last_forward_used_fast_path = fast_path_used
        y_1_2d = ys[0].reshape(batch, -1, h, w)
        y_2_2d = torch.flip(ys[1], dims=[-1]).reshape(batch, -1, h, w)
        y_3_2d = ys[2].reshape(batch, -1, w, h).transpose(2, 3)
        y_4_2d = torch.flip(ys[3], dims=[-1]).reshape(batch, -1, w, h).transpose(2, 3)

        y_out = y_1_2d + y_2_2d + y_3_2d + y_4_2d
        y_out = y_out * F.silu(z_gate, inplace=False)
        return self.out_proj(y_out)


class VMambaBlock(nn.Module):
    """VSS/SS2D-inspired block using four-directional selective scan."""

    def __init__(
        self,
        c1: int,
        c2: int = None,
        expand: int = 1,
        mlp_ratio: float = 4.0,
        d_state: int = 16,
        **kwargs,
    ):
        super().__init__()
        if c2 is not None and c1 != c2:
            raise ValueError(
                f"VMambaBlock requires input channels (c1={c1}) "
                f"to equal output channels (c2={c2})."
            )
        self.c1 = c1
        self.c2 = c1
        self.norm1 = LayerNorm2d(c1)
        self.ss2d = SS2D(c1, d_state=d_state, expand=expand)
        self.norm2 = LayerNorm2d(c1)

        hidden_dim = int(c1 * mlp_ratio)
        self.mlp = nn.Sequential(
            nn.Conv2d(c1, hidden_dim, 1, bias=False),
            nn.SiLU(inplace=False),
            nn.Conv2d(hidden_dim, c1, 1, bias=False),
        )
        self.last_forward_used_fast_path = False

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.ss2d(self.norm1(x))
        self.last_forward_used_fast_path = getattr(
            self.ss2d, "last_forward_used_fast_path", False
        )
        x = x + y
        x = x + self.mlp(self.norm2(x))
        return x
