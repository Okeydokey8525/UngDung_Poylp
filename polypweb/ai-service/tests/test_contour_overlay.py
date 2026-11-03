from types import SimpleNamespace
import numpy as np
import main


def test_contour_is_drawn_along_mask_polygon():
    image = np.zeros((100, 100, 3), dtype=np.uint8)
    square = np.array([[20, 20], [80, 20], [80, 80], [20, 80]], dtype=np.float32)
    result = SimpleNamespace(masks=SimpleNamespace(xy=[square]))

    outlined = main.draw_polyp_contours(image, result)

    assert tuple(outlined[20, 50]) == main.CONTOUR_COLOR_BGR  # on the top edge
    assert tuple(outlined[50, 50]) == (0, 0, 0)               # interior keeps the plotted fill


def test_no_masks_leaves_image_unchanged():
    image = np.full((10, 10, 3), 7, dtype=np.uint8)
    for result in (SimpleNamespace(masks=None), SimpleNamespace(masks=SimpleNamespace(xy=[]))):
        assert np.array_equal(main.draw_polyp_contours(image, result), image)
