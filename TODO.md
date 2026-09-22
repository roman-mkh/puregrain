# TODO / Future Improvements

## Architecture
- [ ] ditherImage: alias `Array Number` to PixelRow
- [ ] ditherImage: LL.List - maybe define custom impl here (diff to typeclass Fifo)

## Backend variants
- [ ] Полиморфная (по `Traversable f`) версия `ditherRow`/`ditherImage` вместо специализированной под `Array` — сравнить производительность (Array.mapAccumL vs Data.Traversable.mapAccumL).
- [ ] ST-based backend (кольцевой буфер, мутабельные массивы) — сравнить производительность с classic (FIFO/Lazy List) версией.
- [x] Data.Sequence-based Fifo вместо Data.List.Lazy — сравнить. (`Seq` is the production default `Fifo` backend — see `docs/benchmarks.md`.)

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
- [ ] generate test-input.png  as well the same way as benchmark images
- [x] Перейти с простых `Test.Assert`-тестов на `purescript-spec` (describe/it) для более структурированного вывода.
- [x] Добавить `purescript-quickcheck` и property-based тесты, начиная с:
  - `prop_backendsAgree` — реализовано как `Test.Dither.DiffusionMechanicsSpec`: все четыре `Fifo`-бэкенда (`Seq`, `List.Lazy`, `List`, `Array`) сверяются со независимым ST-based reference (`Test.Dither.Reference`), а не только друг с другом.
  - Инвариант длины выходной строки/картинки — не отдельная property, но покрыт неявно: `===` на `Array` уже требует равной длины, так что несовпадение длины валит тест.
  - [ ] Инвариант детерминизма для константного входа — всё ещё не проверен отдельной property (тривиально верен для чистых функций, но explicit-тест отсутствует).
- [x] `Arbitrary`-генераторы для `Kernel` (валидные ядра: сумма весов ≈ 1.0, хотя бы один forward и один downward offset) и для тестовых изображений разных размеров. (`Test.Dither.Arbitrary` — `TestKernel`/`TestImage`; заметка: сгенерированные ядра НЕ гарантируют сумму весов ≈ 1.0 явно, просто случайные веса в [0,1].)
- [x] `purescript-spec` также даст удобный selective test run (--example "pattern"/focus), не только структурированный вывод — учтено, переход уже сделан.
- [ ] Use 'test-inpit.png' of different size as benchmark images. merge generation into 1 script (with scaling ability).
      without parameters it should generate 256x256 that can be used for visual control, other images should be integrated
      to automation performatce tests.


## Kernels
нужна функция normalizeKernel/fillGaps, которая на входе берёт Kernel, а на выходе гарантирует, что для каждого dy от 1 до maxDepth есть все offset'ы в согласованном диапазоне dx (недостающие — добавляются с weight=0.0), чтобы каждый слой past[i]/future[i] имел одинаковую, предсказуемую форму (тот же набор FIFO по количеству и порядку) для любого dy.