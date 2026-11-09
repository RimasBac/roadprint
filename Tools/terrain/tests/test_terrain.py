import os, sys, tempfile, unittest
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import rpterrain as T
import prepare_terrain as P

N = np.nan


def band(elev, land, lake, w=None):
    elev = np.array(elev, dtype=np.float32)
    land = np.array(land, dtype=bool)
    lake = np.array(lake, dtype=bool)
    w = np.ones(elev.shape[0]) if w is None else w
    return T.aggregate_band(elev, land, lake, w)


def full(v, shape=(4, 4)):
    return np.full(shape, v)


class Aggregate(unittest.TestCase):
    def test_land_mean_and_rounding_half_up(self):
        e = full(0.0); e[0, 0] = 8.0  # mean 0.5 -> 1
        h, w = band(e, full(True), full(False))
        self.assertEqual(h[0, 0], 1); self.assertFalse(w[0, 0])
        e = full(-0.0); e[0, 0] = -8.0  # mean -0.5 -> 0 (floor(x+.5)), deterministic
        h, _ = band(e, full(True), full(False))
        self.assertEqual(h[0, 0], 0)

    def test_negative_land_preserved(self):
        h, w = band(full(-86.0), full(True), full(False))   # Dead Sea / Death Valley style
        self.assertEqual(h[0, 0], -86); self.assertFalse(w[0, 0])

    def test_ocean_is_sea_level_regardless_of_bathymetry(self):
        h, w = band(full(-4000.0), full(False), full(False))
        self.assertEqual(h[0, 0], 0); self.assertTrue(w[0, 0])

    def test_classification_ignores_elevation_sign(self):
        # land below sea level stays land; ocean above 0 (bad data) is still ocean
        h, w = band(full(-10.0), full(True), full(False)); self.assertFalse(w[0, 0])
        h, w = band(full(+10.0), full(False), full(False)); self.assertTrue(w[0, 0]); self.assertEqual(h[0, 0], 0)

    def test_lake_keeps_surface_height_and_is_water(self):
        h, w = band(full(1897.0), full(True), full(True))    # lake wins over land polygon
        self.assertEqual(h[0, 0], 1897); self.assertTrue(w[0, 0])

    def test_mixed_cell_majority_and_land_wins_ties(self):
        land = np.zeros((4, 4), bool); land[:, :2] = True      # 8 land / 8 ocean: tie
        e = full(100.0); e[:, 2:] = -50.0
        h, w = band(e, land, full(False))
        self.assertFalse(w[0, 0]); self.assertEqual(h[0, 0], 100)     # land wins, ignores ocean samples
        land[:, 1] = False                                            # 4 land / 12 ocean
        h, w = band(e, land, full(False))
        self.assertTrue(w[0, 0]); self.assertEqual(h[0, 0], 0)

    def test_weights_are_area_weighted(self):
        e = full(0.0); e[:2, :] = 100.0
        w = np.array([3.0, 3.0, 1.0, 1.0])
        h, _ = band(e, full(True), full(False), w)
        self.assertEqual(h[0, 0], 75)

    def test_nodata_excluded_from_mean_but_counts_toward_area(self):
        e = full(200.0); e[:, :2] = N
        h, w = band(e, full(True), full(False))
        self.assertEqual(h[0, 0], 200); self.assertFalse(w[0, 0])

    def test_all_nodata_land_cell_stays_nodata_not_zero(self):
        h, w = band(full(N), full(True), full(False))
        self.assertEqual(h[0, 0], T.NODATA); self.assertFalse(w[0, 0])

    def test_all_nodata_lake_cell_stays_nodata(self):
        h, w = band(full(N), full(True), full(True))
        self.assertEqual(h[0, 0], T.NODATA); self.assertTrue(w[0, 0])

    def test_output_shape_and_independent_cells(self):
        e = np.zeros((8, 8), dtype=np.float32); e[:4, 4:] = 7.0
        land = np.ones((8, 8), bool)
        h, _ = band(e, land, np.zeros((8, 8), bool))
        self.assertEqual(h.shape, (2, 2)); self.assertEqual(h.tolist(), [[0, 7], [0, 0]])

    def test_rejects_non_multiple(self):
        with self.assertRaises(ValueError):
            band(np.zeros((5, 4)), np.ones((5, 4)), np.zeros((5, 4)))

    def test_extreme_heights_fit_int16_and_never_hit_sentinel(self):
        h, _ = band(full(40000.0), full(True), full(False)); self.assertEqual(h[0, 0], 32767)
        h, _ = band(full(-40000.0), full(True), full(False)); self.assertEqual(h[0, 0], -32767)

    def test_lat_weights_shrink_toward_poles(self):
        w = T.lat_weights(0, 21600, 21600)
        self.assertTrue(w[0] < 0.001 and w[10800] > 0.999 and abs(w[0] - w[-1]) < 1e-12)


class Tiles(unittest.TestCase):
    def test_pack_unpack_roundtrip(self):
        rng = np.random.default_rng(1)
        h = rng.integers(-500, 6000, (6, 6), dtype=np.int16); h[0, 0] = T.NODATA
        w = rng.integers(0, 2, (6, 6)).astype(bool)
        data = T.pack_tile(h, w)
        self.assertEqual(len(data), T.tile_size(6, 6))
        h2, w2 = T.unpack_tile(data, 6, 6)
        self.assertTrue((h == h2).all() and (w == w2).all())

    def test_byte_order_and_bit_order(self):
        h = np.zeros((8, 1), np.int16); h[0, 0] = 0x0102
        w = np.zeros((8, 1), bool); w[0, 0] = True; w[3, 0] = True
        data = T.pack_tile(h, w)
        self.assertEqual(data[:2], bytes([0x02, 0x01]))      # little-endian
        self.assertEqual(data[16], 0b00001001)              # LSB first, row-major

    def test_tile_size_and_budget_for_real_grid(self):
        self.assertEqual(T.GRID_COLS * T.GRID_ROWS * 2, 116_640_000)
        self.assertAlmostEqual(116_640_000 / 2**20, 111.2366, places=3)  # ADR rounds to 111.24 MiB
        total = (T.GRID_COLS // T.TILE_COLS) * (T.GRID_ROWS // T.TILE_ROWS) * T.tile_size()
        self.assertEqual(T.tile_size(), 619_650)
        self.assertEqual(total, 123_930_000)
        self.assertLessEqual(total, 120 * 2**20)

    def test_tiles_partition_grid_without_duplicate_borders(self):
        h = np.arange(12 * 6, dtype=np.int16).reshape(6, 12)
        w = np.zeros((6, 12), bool)
        tiles = {(ty, tx): T.unpack_tile(d, 3, 6)[0] for ty, tx, d in T.split_tiles(h, w, 3, 6)}
        self.assertEqual(len(tiles), 4)
        back = np.block([[tiles[0, 0], tiles[0, 1]], [tiles[1, 0], tiles[1, 1]]])
        self.assertTrue((back == h).all())
        self.assertEqual(sum(t.size for t in tiles.values()), h.size)

    def test_split_requires_whole_tiles(self):
        with self.assertRaises(ValueError):
            list(T.split_tiles(np.zeros((5, 5), np.int16), np.zeros((5, 5), bool), 3, 3))

    def test_unpack_rejects_wrong_size(self):
        with self.assertRaises(ValueError):
            T.unpack_tile(b"\0" * 10, 6, 6)

    def test_checksums_deterministic(self):
        h = np.arange(36, dtype=np.int16).reshape(6, 6); w = np.eye(6, dtype=bool)
        self.assertEqual(T.sha256_bytes(T.pack_tile(h, w)), T.sha256_bytes(T.pack_tile(h.copy(), w.copy())))
        with tempfile.NamedTemporaryFile() as f:
            f.write(b"abc"); f.flush()
            self.assertEqual(T.sha256_file(f.name), T.sha256_bytes(b"abc"))


class Grid(unittest.TestCase):
    def test_cell_index_edges(self):
        self.assertEqual(T.cell_index(90, -180), (0, 0))
        self.assertEqual(T.cell_index(-90, 179.999999), (5399, 10799))
        self.assertEqual(T.cell_index(0, 0), (2700, 5400))
        self.assertEqual(T.cell_index(89.99, 0)[0], 0)

    def test_antimeridian_wraps(self):
        self.assertEqual(T.cell_index(10, 180)[1], 0)
        self.assertEqual(T.cell_index(10, -180)[1], 0)
        self.assertEqual(T.cell_index(10, 190)[1], T.cell_index(10, -170)[1])

    def test_reader_wraps_columns_and_clamps_rows(self):
        h = np.arange(12 * 6, dtype=np.int16).reshape(6, 12); w = np.zeros((6, 12), bool)
        with tempfile.TemporaryDirectory() as d:
            for ty, tx, data in T.split_tiles(h, w, 3, 6):
                open(os.path.join(d, T.tile_name(ty, tx)), "wb").write(data)
            r = T.Reader(d, 6, 12, 3, 6)
            self.assertEqual(r.cell(0, 12)[0], h[0, 0])         # wrap east
            self.assertEqual(r.cell(0, -1)[0], h[0, 11])        # wrap west
            self.assertEqual(r.cell(-3, 0)[0], h[0, 0])         # north pole clamps
            self.assertEqual(r.cell(99, 0)[0], h[5, 0])         # south pole clamps
            reg, _ = r.region(1, 4, 10, 14)                     # crosses tile border and seam
            self.assertTrue((reg == h[1:4, [10, 11, 0, 1]]).all())


class Rasterize(unittest.TestCase):
    def test_polygon_with_hole(self):
        import shapefile
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "t")
            with shapefile.Writer(path, shapeType=shapefile.POLYGON) as w:
                w.field("a", "C")
                outer = [(-90, 45), (90, 45), (90, -45), (-90, -45), (-90, 45)]          # clockwise
                hole = [(-30, 15), (-30, -15), (30, -15), (30, 15), (-30, 15)]           # counter-clockwise
                w.poly([outer, hole]); w.record("x")
            a = P.Polygons(path + ".shp", 360, 180).band(0, 180)
            b = P.Polygons(path + ".shp", 360, 180).band(50, 40)
            self.assertTrue((a[50:90] == b).all())   # banding is equivalent to full raster
            self.assertTrue(a[60, 100])          # in ring, outside hole
            self.assertFalse(a[90, 180])         # inside hole
            self.assertFalse(a[10, 10])          # outside ring
            self.assertFalse(a[90, 50])          # west of ring
            # edges are filled inclusively (documented ~half-sample tolerance), so allow a boundary band
            self.assertLessEqual(abs(int(a.sum()) - (180 * 90 - 60 * 30)), 2 * (180 + 90) + 2 * (60 + 30))


class LandCover(unittest.TestCase):
    def test_reduce_majority_white_is_no_cover_and_coast_keeps_colour(self):
        rgb = np.full((3, 6, 3), 255, np.uint8)
        rgb[:, 3:] = (10, 90, 30)                            # right cell: all green
        rgb[0, 0] = (200, 0, 0); rgb[1, 0] = (200, 0, 0)     # left cell: 2 of 9 red, 7 white -> none
        mean, cover = T.reduce_landcover(rgb)
        self.assertEqual(cover.tolist(), [[False, True]])
        self.assertEqual(mean[0, 1].tolist(), [10, 90, 30])
        rgb[:, :3] = (10, 90, 30); rgb[0, 0] = rgb[0, 1] = rgb[0, 2] = 255   # coast: 3 white of 9
        mean, cover = T.reduce_landcover(rgb)
        self.assertTrue(cover[0, 0]); self.assertEqual(mean[0, 0].tolist(), [10, 90, 30])

    def test_reduce_rejects_bad_shape(self):
        with self.assertRaises(ValueError):
            T.reduce_landcover(np.zeros((4, 3, 3), np.uint8))

    def test_palette_is_deterministic_and_sorted(self):
        rng = np.random.default_rng(3)
        cols = np.unique(rng.integers(0, 256, (500, 3)), axis=0)
        w = rng.integers(1, 50, len(cols))
        p1 = T.median_cut_palette(cols, w, 16); p2 = T.median_cut_palette(cols.copy(), w.copy(), 16)
        self.assertTrue((p1 == p2).all()); self.assertEqual(p1.shape, (16, 3))
        self.assertEqual(sorted(map(tuple, p1.tolist())), list(map(tuple, p1.tolist())))

    def test_palette_pads_when_few_colours(self):
        p = T.median_cut_palette(np.array([[1, 2, 3], [9, 9, 9]]), np.array([1, 1]), 5)
        self.assertEqual(p.shape, (5, 3))

    def test_build_landcover_index_zero_reserved(self):
        rgb = np.full((6, 6, 3), 255, np.uint8)
        rgb[:3, :3] = (0, 100, 0); rgb[3:, 3:] = (200, 180, 120)
        idx, pal = T.build_landcover(rgb, palette_size=4)
        self.assertEqual(pal.shape, (5, 3))     # reserved slot + palette entries
        self.assertEqual(idx.tolist()[0][1], 0); self.assertEqual(idx.tolist()[1][0], 0)
        self.assertNotEqual(idx[0, 0], 0); self.assertNotEqual(idx[1, 1], 0)
        self.assertEqual(pal[0].tolist(), [0, 0, 0])
        self.assertEqual(pal[idx[0, 0]].tolist(), [0, 100, 0])

    def test_quantize_nearest_lowest_index_on_tie(self):
        pal = np.array([[0, 0, 0], [10, 0, 0], [10, 0, 0]], np.uint8)
        self.assertEqual(T.quantize(np.array([[9.0, 0, 0], [1.0, 0, 0]]), pal, chunk=1).tolist(), [1, 0])

    def test_byte_budget_with_landcover(self):
        raw = 200 * T.tile_size() + T.LC_COLS * T.LC_ROWS
        self.assertEqual(T.LC_COLS * T.LC_ROWS, 14_580_000)
        self.assertLess(raw + 64 * 1024, 140 * 2**20)          # manifest allowance
        self.assertAlmostEqual(raw / 2**20, 132.09, places=1)  # elevation + mask + land cover


class LakesAndFloors(unittest.TestCase):
    def lake_fixture(self):
        # 8x8 samples: lake id 1 in the middle 4x4, land around it at ~183 m, lake floor -250 m
        e = np.full((8, 8), 183.0, np.float32); e[2:6, 2:6] = -250.0
        e[0, 0] = 900.0                       # far land must not influence the level
        ids = np.zeros((8, 8), np.int32); ids[2:6, 2:6] = 1
        return e, ids

    def test_ring_samples_are_land_within_one_sample_of_lake(self):
        e, ids = self.lake_fixture()
        lonly = ids == 0
        ep = np.vstack([np.full((1, 8), np.nan, np.float32), e, np.full((1, 8), np.nan, np.float32)])
        ip = np.vstack([np.zeros((1, 8), np.int32), ids, np.zeros((1, 8), np.int32)])
        lp = np.vstack([np.zeros((1, 8), bool), lonly, np.zeros((1, 8), bool)])
        lid, vals = T.ring_samples(ep, lp, ip)
        self.assertEqual(len(lid), 36 - 16)         # 6x6 box minus the 4x4 lake
        self.assertTrue((lid == 1).all() and (vals == 183.0).all())

    def test_lake_is_flat_at_shore_level_not_lake_floor(self):
        e, ids = self.lake_fixture()
        level = T.flat_level([183.0, 183.0, 185.0])
        self.assertEqual(level, 183)
        flat = T.apply_lake_levels(e, ids, {1: level})
        self.assertTrue((flat[2:6, 2:6] == 183).all()); self.assertEqual(flat[0, 0], 900)
        big = np.zeros((8, 8), np.int32); big[:4, :4] = 1                 # lake filling one whole output cell
        flat = T.apply_lake_levels(np.where(big > 0, -250.0, 183.0).astype(np.float32), big, {1: 183})
        h2, w2 = T.aggregate_band(flat, np.ones((8, 8), bool), big > 0, np.ones(8))
        self.assertTrue(w2[0, 0] and h2[0, 0] == 183)                     # water bit set, shore level, not -250
        self.assertFalse(w2[1, 1])

    def test_lake_without_level_keeps_source_values(self):
        e, ids = self.lake_fixture()
        self.assertTrue((T.apply_lake_levels(e, ids, {})[2:6, 2:6] == -250).all())

    def test_flat_level_median_and_rounding(self):
        self.assertEqual(T.flat_level([1, 2, 3, 100]), 3)       # median 2.5 -> 3
        self.assertEqual(T.flat_level([-3, -2]), -2)            # -2.5 -> -2 (half toward +inf)

    def test_land_floor_clamps_value_not_classification(self):
        e = np.array([[-2849.0, -440.0, -430.0, -85.0, np.nan, 10.0]], np.float32)
        land = np.ones((1, 6), bool)
        out, n = T.clamp_land(e, land)
        self.assertEqual(n, 1)
        self.assertEqual(out[0, :4].tolist(), [-440.0, -440.0, -430.0, -85.0]); self.assertTrue(np.isnan(out[0, 4]))
        out, n = T.clamp_land(e, np.zeros((1, 6), bool)); self.assertEqual(n, 0)   # non-land untouched
        self.assertEqual(out[0, 0], -2849.0)

    def test_clamped_fjord_cell_stays_land_at_floor(self):
        e = np.full((4, 4), -2849.0, np.float32)
        e, _ = T.clamp_land(e, np.ones((4, 4), bool))
        h, w = band(e, full(True), full(False))
        self.assertEqual(h[0, 0], -440); self.assertFalse(w[0, 0])

    def test_inland_sea_and_wraparound_labels(self):
        h = np.zeros((6, 12), np.int16); water = np.zeros((6, 12), bool); ocean = np.zeros((6, 12), bool)
        h[:] = 30; water[2:4, 4:8] = True; ocean[2:4, 4:8] = True; h[water] = 0   # enclosed sea, shore 30 m
        member, level = T.inland_sea(ocean, h, water, 2, 5)
        self.assertEqual(int(member.sum()), 8); self.assertEqual(level, 30)
        ocean2 = np.zeros((6, 12), bool); ocean2[1, 0] = ocean2[1, 11] = True
        lab = T.label_wrap(ocean2); self.assertEqual(lab[1, 0], lab[1, 11]); self.assertNotEqual(lab[1, 0], 0)
        self.assertEqual(T.inland_sea(ocean, h, water, 0, 0), (None, None))   # land cell

    def test_record_hole_does_not_erase_other_records(self):
        import shapefile
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "t")
            with shapefile.Writer(path, shapeType=shapefile.POLYGON) as w:
                w.field("a", "C")
                w.poly([[(-90, 45), (90, 45), (90, -45), (-90, -45), (-90, 45)],
                        [(-30, 15), (-30, -15), (30, -15), (30, 15), (-30, 15)]]); w.record("big with hole")
                w.poly([[(-5, 5), (5, 5), (5, -5), (-5, -5), (-5, 5)]]); w.record("island in the hole")
            p = P.Polygons(path + ".shp", 360, 180)
            a = p.band(0, 180)
            self.assertTrue(a[90, 180])          # island pixel survives although it lies in the other record's hole
            self.assertFalse(a[90 - 12, 180])    # hole elsewhere still empty
            ids = p.band(0, 180, ids=True)
            self.assertEqual(int(ids[90, 180]), 2); self.assertEqual(int(ids[60, 100]), 1)


if __name__ == "__main__":
    unittest.main()
