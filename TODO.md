# TODO / Future Improvements

## Architecture
- [ ] **Blocker for publishing to the registry/Pursuit:** the library depends on `sequences` through a git fork
      (`workspace.extraPackages` in `spago.yaml`: flip111/purescript-sequences, pinned commit). A registry package
      can't depend on a git package — needs the fork's changes released to the registry (upstream or as a new
      package), or `Seq` replaced/vendored. Decide at the public-interface step.
      Option worth trying first: our own `Fifo` instance as an Okasaki two-list ("banker's") queue — no
      dependency at all. `Seq` was chosen only for cheap concatenation in `replace`, but `replace skip` can be
      `skip` dequeues + `skip` enqueues: O(skip), skip <= kernel reach (<= 3). Enqueue/dequeue are O(1)
      amortized as long as each queue version is used once, which is how `step`/`ditherRow` use them.
      Prove it as a 5th backend in `DiffusionMechanicsSpec`, then benchmark against `Seq`.
- [ ] ditherImage: alias `Array Number` to PixelRow
- [ ] ditherImage: LL.List - maybe define custom impl here (diff to typeclass Fifo)

## Backend variants
- [ ] Полиморфная (по `Traversable f`) версия `ditherRow`/`ditherImage` вместо специализированной под `Array` — сравнить производительность (Array.mapAccumL vs Data.Traversable.mapAccumL).
- [ ] ST-based backend (кольцевой буфер, мутабельные массивы) — сравнить производительность с classic (FIFO/Lazy List) версией.
- [x] Data.Sequence-based Fifo вместо Data.List.Lazy — сравнить. (`Seq` is the production default `Fifo` backend — see `docs/benchmarks.md`.)
- [ ] Benchmark `Dither.Pixel.nearestLevel`: O(N) linear scan today vs. sort-once + binary search O(log N) (see the `TODO(benchmark)` note on it). Only worth changing if it shows up at realistic level counts.

## Algorithm configuration
- [ ] Ostromoukhov's Variable Error Diffusion 
- [ ] Обобщить `Kernel + quantize` в единую конфигурацию алгоритма (см. раннюю идею `DitherAlgo` record). 
- [ ] Рассмотреть typeclass + Reader Monad для протаскивания конфигурации алгоритма через весь pipeline, вместо явной передачи параметрами.
- [ ] Pass custom user data for itsown impl of `quantize`
- [ ] Maybe `quantize` has to know some stateful imformation as begin row-

## Application
- [ ] Browser demo (Canvas API через FFI, purescript-canvas) — сравнение всех вариантов дизеринга visually.
- [ ] Метрики качества (PSNR/SSIM) для сравнения алгоритмов.

## Testing infrastructure
- [x] generate test-input.png  as well the same way as benchmark images (done: one generator, `scripts/generate-images.mjs`, for both — see `docs/test-images.md`)
- [x] Перейти с простых `Test.Assert`-тестов на `purescript-spec` (describe/it) для более структурированного вывода.
- [x] Добавить `purescript-quickcheck` и property-based тесты, начиная с:
  - `prop_backendsAgree` — реализовано как `Test.Dither.DiffusionMechanicsSpec`: все четыре `Fifo`-бэкенда (`Seq`, `List.Lazy`, `List`, `Array`) сверяются со независимым ST-based reference (`Test.Dither.Reference`), а не только друг с другом.
  - Инвариант длины выходной строки/картинки — не отдельная property, но покрыт неявно: `===` на `Array` уже требует равной длины, так что несовпадение длины валит тест.
  - [ ] Инвариант детерминизма для константного входа — всё ещё не проверен отдельной property (тривиально верен для чистых функций, но explicit-тест отсутствует).
- [x] `Arbitrary`-генераторы для `Kernel` (валидные ядра: сумма весов ≈ 1.0, хотя бы один forward и один downward offset) и для тестовых изображений разных размеров. (`Test.Dither.Arbitrary` — `TestKernel`/`TestImage`; заметка: сгенерированные ядра НЕ гарантируют сумму весов ≈ 1.0 явно, просто случайные веса в [0,1].)
- [x] `purescript-spec` также даст удобный selective test run (--example "pattern"/focus), не только структурированный вывод — учтено, переход уже сделан.
- [x] Use 'test-inpit.png' of different size as benchmark images. merge generation into 1 script (with scaling ability).
      without parameters it should generate 256x256 that can be used for visual control, other images should be integrated
      to automation performatce tests.
      (done: `scripts/generate-images.mjs` — gray + truecolor composites, `--size`/`--sizes`/`WxH`; default changed to 512² by
      decision, see `docs/test-images.md`. Benchmark automation on these images is still to come — `benchmark.sh` only
      got the minimal switch to the new generator.)
- [x] `Test.Dither.Row`, `Test.Dither.Step` — migrated to
      `Test.Dither.RowSpec`/`Test.Dither.StepSpec` (property tests +
      shape invariants + ported regression examples + edge cases), old
      originals deleted, dead `Test.Main` references removed.
- [ ] `Test.Dither.Image`, `Test.Dither.Playground` are still leftover
      `Test.Assert`-style modules from before the `purescript-spec`
      migration — they compile but **don't actually run**: `Test.Main`
      only calls `discoverAndRunSpecs [...] """Dither\..*Spec"""`,
      neither module name ends in `Spec`, and the old `.main` call for
      `Image` in `Test.Main` is commented out (`Playground` was never
      called from `Test.Main` at all). Write `*Spec` versions of
      whatever's still worth keeping from them, then delete the two
      dead originals once migrated — same treatment `Row`/`Step` just got.


## Future library extension directions (not in scope now)
- [ ] CMY/CMYK pixel types + GCR/UCR (gray component replacement / under
      color removal). Algebraically CMY(K) is identical to RGB(A) — same
      independent-`Ring`-channel shape, same `Scalable` — so the type
      itself is cheap to add later (a straightforward newtype + instances,
      same as RGB/RGBA, no new abstraction needed). The real work is GCR/
      UCR: deriving K from C/M/Y is a color-management step that has to
      happen *before* dithering, not something plain independent-channel
      error diffusion gives you — naive 4-independent-channel diffusion is
      representable in this architecture today but isn't real print-
      quality CMYK output on its own (no per-channel screen angles, no
      moiré avoidance). Needs a concrete print/halftone target to justify.
- [ ] `distance2Lab` — CIELAB-space distance metric for `Dither.Palette`,
      as a second argument to plug into `compilePalette`/
      `compilePaletteFromArray` alongside `distance2` (that's exactly what
      `CompiledPalette` packing the distance function was designed to make
      swappable — see `Dither.Palette`). Requires an RGB→Lab conversion
      (through XYZ, with a chosen white point/gamma assumption) that
      doesn't exist yet anywhere in this codebase.

## Kernels
нужна функция normalizeKernel/fillGaps, которая на входе берёт Kernel, а на выходе гарантирует, что для каждого dy от 1 до maxDepth есть все offset'ы в согласованном диапазоне dx (недостающие — добавляются с weight=0.0), чтобы каждый слой past[i]/future[i] имел одинаковую, предсказуемую форму (тот же набор FIFO по количеству и порядку) для любого dy.