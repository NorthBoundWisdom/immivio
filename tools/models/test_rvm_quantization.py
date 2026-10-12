"""Conversion-tool tests; run in the AI Python environment with NumPy/ONNX installed."""
import unittest
import numpy as np
from prepare_rvm_mnn import check_alpha_quantization


class AlphaQuantization(unittest.TestCase):
    def test_positive_half_ties_use_lround(self):
        alpha = np.array([0.5 / 255, 2.5 / 255], dtype=np.float32)
        result = check_alpha_quantization(alpha, alpha, alpha * 255 + 0.5)
        self.assertEqual(result['max_quantized_difference'], 0)
        self.assertEqual(result['export_invalid_pixels'], 0)

    def test_measured_error_explains_a_single_threshold_crossing(self):
        reference = np.array([15.50002384185791 / 255], dtype=np.float32)
        actual = np.array([15.499579429626465 / 255], dtype=np.float32)
        result = check_alpha_quantization(reference, actual, actual * 255 + 0.5)
        self.assertEqual(result['ambiguous_pixels'], 1)
        self.assertEqual(result['invalid_pixels'], 0)
        self.assertEqual(result['export_invalid_pixels'], 0)

    def test_an_incorrect_export_offset_is_rejected(self):
        alpha = np.array([0.2, 0.4, 0.8], dtype=np.float32)
        result = check_alpha_quantization(alpha, alpha, alpha * 255 + 1.5)
        self.assertGreater(result['invalid_pixels'], 0)
        self.assertGreater(result['export_invalid_pixels'], 0)

    def test_nonfinite_values_are_rejected(self):
        alpha = np.array([float('nan')], dtype=np.float32)
        with self.assertRaises(ValueError):
            check_alpha_quantization(alpha, alpha, alpha)


if __name__ == '__main__':
    unittest.main()
