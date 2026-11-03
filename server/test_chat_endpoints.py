import unittest
import sys
import os

# Add server directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from main import get_channel_id

class TestChatEndpointsAndLogic(unittest.TestCase):
    def test_canonical_channel_id(self):
        # Case insensitivity and whitespace tolerance
        id1 = get_channel_id("ride_123", "usr_TANVIR", "usr_biker")
        id2 = get_channel_id("ride_123", "usr_biker", "usr_tanvir")
        id3 = get_channel_id("ride_123", " usr_tanvir ", "usr_biker ")

        self.assertEqual(id1, id2)
        self.assertEqual(id1, id3)
        self.assertEqual(id1, "ride_123__usr_biker__usr_tanvir")

    def test_same_user_fallback(self):
        id_same = get_channel_id("ride_456", "usr_A", "usr_a")
        self.assertEqual(id_same, "ride_456")

if __name__ == '__main__':
    unittest.main()

