import copy
import json
import tempfile
import unittest
from pathlib import Path

import render

CONFIG = render.load_config()


class ConfigTests(unittest.TestCase):
    def write(self, config):
        path = Path(tempfile.mkdtemp()) / 'scenes.json'
        path.write_text(json.dumps(config))
        return path

    def test_checked_in_scenes_are_valid(self):
        total = sum(scene['seconds'] for scene in CONFIG['scenes'])
        self.assertTrue(15 <= total <= 30)

    def test_rejects_an_image_or_any_unknown_key(self):
        config = copy.deepcopy(CONFIG)
        config['scenes'][0]['image'] = 'Design/appstore/previews/01.png'
        with self.assertRaisesRegex(render.HarnessError, 'expected keys'):
            render.load_config(self.write(config))
        config = copy.deepcopy(CONFIG)
        config['overlay'] = 'logo.png'
        with self.assertRaisesRegex(render.HarnessError, 'expected keys'):
            render.load_config(self.write(config))

    def test_rejects_lengths_outside_the_app_store_range(self):
        config = copy.deepcopy(CONFIG)
        config['scenes'] = config['scenes'][:2]
        with self.assertRaisesRegex(render.HarnessError, '15–30'):
            render.load_config(self.write(config))

    def test_rejects_other_sizes_and_fonts_outside_the_repo(self):
        config = copy.deepcopy(CONFIG)
        config['output']['height'] = 1080
        with self.assertRaisesRegex(render.HarnessError, 'preview size'):
            render.load_config(self.write(config))
        config = copy.deepcopy(CONFIG)
        config['caption']['font'] = '../../etc/font.ttf'
        with self.assertRaisesRegex(render.HarnessError, 'inside the repository'):
            render.load_config(self.write(config))


class PlanTests(unittest.TestCase):
    marks = {'myMap': 140.0, 'filters': 147.0, 'drive': 102.0, 'summary': 118.0, 'cardVideo': 125.0, 'end': 160.0}

    def test_maps_marks_into_the_recording(self):
        cuts = render.plan(CONFIG, self.marks, record_start=100.0, raw_seconds=80.0)
        self.assertEqual(cuts[0]['source_start'], 40.3)
        self.assertEqual(cuts[0]['output_start'], 0.0)
        self.assertEqual(cuts[1]['output_start'], 4.0)
        self.assertEqual(cuts[2]['source_start'], 2.0)

    def test_scene_must_lie_inside_the_recording(self):
        with self.assertRaisesRegex(render.HarnessError, 'outside'):
            render.plan(CONFIG, self.marks, record_start=100.0, raw_seconds=60.0)
        with self.assertRaisesRegex(render.HarnessError, 'outside'):
            render.plan(CONFIG, self.marks, record_start=110.0, raw_seconds=80.0)

    def test_missing_mark(self):
        marks = dict(self.marks)
        del marks['end']
        with self.assertRaisesRegex(render.HarnessError, "no mark 'end'"):
            render.plan(CONFIG, marks, record_start=100.0, raw_seconds=80.0)


class CommandTests(unittest.TestCase):
    def test_the_recording_is_the_only_picture_input(self):
        cuts = render.plan(CONFIG, PlanTests.marks, 100.0, 80.0)
        texts = [Path(f'/tmp/c{i}.txt') for i in range(len(cuts))]
        command = render.render_command(CONFIG, Path('/x/raw.mov'), cuts, texts, Path('/x/out.mp4'),
                                        music=Path('/x/song.m4a'))
        inputs = [command[i + 1] for i, arg in enumerate(command) if arg == '-i']
        self.assertEqual(inputs, ['/x/raw.mov', '/x/song.m4a'])
        graph = command[command.index('-filter_complex') + 1]
        self.assertNotIn('[1:v]', graph)
        self.assertNotIn('overlay', graph)
        self.assertNotIn('movie=', graph)
        self.assertEqual(graph.count('[0:v]trim='), len(cuts))
        self.assertIn('expansion=none', graph)

    def test_mean_difference_skips_the_caption_band(self):
        a = bytes([10] * 4 * 4)
        b = bytes([200] * 4 + [10] * 12)
        self.assertEqual(render.mean_difference(a, b, 4, (0, 2)), 0)
        self.assertGreater(render.mean_difference(a, b, 4, (2, 4)), 0)


class MarkerTests(unittest.TestCase):
    def test_reads_markers_from_an_attachment_export(self):
        folder = Path(tempfile.mkdtemp())
        (folder / 'm.json').write_text(json.dumps({'clock': 'unix', 'marks': {'drive': 1.0}}))
        (folder / 'manifest.json').write_text(json.dumps([{'attachments': [
            {'suggestedHumanReadableName': 'preview-markers_0_ABC.json', 'exportedFileName': 'm.json'}]}]))
        self.assertEqual(render.load_markers(folder)[1], {'drive': 1.0})


if __name__ == '__main__':
    unittest.main()
