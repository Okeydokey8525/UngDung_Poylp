from types import SimpleNamespace
import numpy as np
from PIL import Image
import main


def test_rgb_pil_input_and_fp32_are_preserved():
    image = Image.new("RGB", (4, 3), (240, 12, 20))
    captured = {}

    class Model:
        def predict(self, **kwargs):
            captured.update(kwargs)
            return [SimpleNamespace(
                boxes=None, masks=None,
                plot=lambda: np.zeros((3, 4, 3), dtype=np.uint8),
            )]

    result = main.run_inference(Model(), "cpu", image)
    # RGB ndarray input would be interpreted as BGR by the Ultralytics loader.
    assert captured["source"] is image
    assert captured["source"].getpixel((0, 0)) == (240, 12, 20)
    assert captured["half"] is False
    assert result["maskCount"] == 0
