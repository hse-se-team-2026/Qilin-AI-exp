# Производительность и память UCFS против Spark на бенчмарках Qilin

pin: bd5cf3a7cc8211355dc485927215be98832ebf39

Документ стори E5-S6 (эпик E5, пункт 5 плана AGENTS.md: «Бенчмарков парочку UCFS»). Числа взяты из закоммиченных результатов финального прогона `docs/ucfs-integration/e5-results/` (стори E5-S5a и E5-S5b). Таблицы T1–T8 — дословный вывод `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results`. Ссылка `путь:строка#символ` указывает на код Qilin-AI-exp на коммите из строки `pin` (база ветки этого документа). Код путей `qilin.pta/src`, `qilin.core/src`, `qilin.ucfs/src` и `scripts/ucfs` на этом коммите совпадает с кодом `git-head` прогона из T1, это сверяет `bash acceptance/E5/S5_results.sh`. Механику документа проверяет `bash acceptance/E5/S6_doc.sh`.

Слово «интерпретация» отмечает вывод автора, который код или результаты прямо не утверждают. Утверждение с пометкой о проверке называет команду, файл результатов или место в коде, которые его подтверждают. Отрицательный результат здесь — законный итог: числа не подбирались под ожидание.

Коротко:
- Прогон шёл на арендованной ВМ `gen-8-64` с 8 vCPU (раздел 1). Замеры идут в отдельных JVM, на (бенчмарк, прогон) приходится прогрев и 10 замеров.
- Время Spark здесь — весь `pureRun` Spark, вместе с ленивым построением Jimple, MethodPAG и графа вызовов, а UCFS решает на готовом PAG (раздел 2). Отношение UCFS/Spark поэтому сравнивает разную работу (интерпретация по коду раздела 2).
- На трёх покрытых срезах с самыми большими PAG UCFS-часть в ANALYSIS дольше `pureRun` Spark: на antlr медиана отношения UCFS/Spark 38.75, на bloat 4.68, на chart 2.97 (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T3`).
- На остальных трёх покрытых срезах отношение в ANALYSIS меньше 1: на fop 0.41, на luindex 0.29, на lusearch 0.41. Это не значит, что UCFS быстрее решает ту же задачу (раздел 2).
- Там, где UCFS-часть длится не меньше 5 s, почти всё её время уходит на `parse()` GLL: от 94.2 % до 99.6 % (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T4`).
- Минимальная куча UCFS-прогонов больше, чем у Spark, на всех шести покрытых срезах, приращение — от 32 MB у luindex в ANALYSIS до 4128 MB у antlr в ANALYSIS (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T6`).
- Ответ анализа во всех повторах один и тот же и совпадает с E4 (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T7`).
- Пробы за пределами бюджета дали по одному наблюдению при `-Xmx52g` (раздел 6). antlr в CALL_GRAPH ответил за 1361.72 s, checkstyle в CALL_GRAPH ответил за 569.55 s. bloat в CALL_GRAPH остался без ответа за 3600 s (timeout). luindex с телами JDK в ANALYSIS кончился OutOfMemoryError.

## 1. Методика и конфигурация

Что меряли (E5.md D1). На каждом из 12 бенчмарков `artifact/benchmarks` идут три прогона: `insens` — Spark (`-pta=insens`), `ucfs-ANALYSIS` и `ucfs-CALL_GRAPH` — `-pta=ucfs` с режимом связывания `-ucfsbinding=ANALYSIS` или `-ucfsbinding=CALL_GRAPH`. Spark — контекстно-нечувствительный анализ Андерсена в Qilin (`Lhotak2003Scaling`, `He2022Qilin`). Командная строка у всех прогонов одна и та же, кроме `-pta`, `-ucfsbinding` и `-Xmx`: опции `artifact/run.py`, журнал рефлексии, `-exclude` пакетов JDK и `-ucfsseam` (`scripts/ucfs/e5-lib.sh:98-108#e5_command`). Опций сверки `-ucfscompare` и дампа `-ucfspt` в прогонах нет: это проверка ответа, а не стоимость анализа, и в E4 они входили во время и RSS.

Как меряли (D4, D5). Каждый прогон — отдельная JVM с холодным стартом (`scripts/ucfs/e5-bench.sh:187-198#e5_run`). Замеры идут повтор за повтором, внутри повтора — бенчмарк за бенчмарком, внутри бенчмарка — три прогона, порядок которых в повторе `k` сдвинут по кругу на `k` (`scripts/ucfs/e5-bench.sh:187-198#rot`). Так дрейф машины и позиция внутри повтора делятся между прогонами поровну (интерпретация, D4). Повтор 0 — прогрев: его цель — файловый кэш ОС (jar и бенчмарки), в статистику он не входит (D4). Далее 10 замеров, как в `Blackburn2025Rethinking` (раздел 6.1 статьи: 10 запусков и 95 % доверительные интервалы). Лимит прогона — 900 s, куча `-Xmx16g`. CALL_GRAPH на antlr, bloat и checkstyle в повторы не входил (статус skipped в T3–T7): в E4 antlr и bloat не уложились в 900 s, и эти три прогона ушли в пробы (раздел 6, D4).

Статистика (D5). По 10 замерам считаются медиана, min–max, межквартильный размах IQR и коэффициент вариации CV (стандартное отклонение к среднему). Доверительный интервал медианы строится по порядковым статистикам без допущений о распределении: при 10 замерах это `[x(2), x(9)]` с покрытием 97.9 % (проверено: `acceptance/E5/e5tables.py:11-14#median_ci`). Отношение UCFS/Spark — медиана парных отношений одного повтора с таким же интервалом. Проверок гипотез нет. Где интервал отношения не содержит 1, различие видно и без них (интерпретация, D5).

Почему холодные JVM. Утверждение E5 — о времени одного запуска анализа на программу, а `Blackburn2025Rethinking` (страница 5, рекомендация P1) требует, чтобы дизайн эксперимента соответствовал утверждению. Поэтому загрузка классов и JIT входят во время (интерпретация, D4).

Память (D3). Основная мера — минимальная куча: наименьший `-Xmx` с шагом 16 MB, при котором прогон завершается с тем же ответом и укладывается в три времени эталонного прогона при `-Xmx16g`, но не меньше 60 s на шаг. Её ищет бинарный поиск от 64 до 16384 MB с двумя подтверждающими шагами на 32 MB выше и ниже итога (`scripts/ucfs/e5-minheap.sh:282-294#take`). `Blackburn2025Rethinking` (страница 5) пишет, что минимальная куча отражает пиковое использование памяти, и советует задавать кучу кратной минимальной (рекомендация H2). Пик RSS процесса (GNU time) — вторичная мера: при фиксированной `-Xmx16g` он зависит от того, сколько кучи занял сборщик G1, а не от того, сколько нужно анализу (интерпретация, D3). Минимальная куча искалась на шести покрытых срезах.

Срезы и покрытие (E4 D3, D14). Тела JDK исключены, поэтому граф каждого бенчмарка — срез программы, а не программа DaCapo (`Blackburn2006Dacapo`) целиком. Покрытие — доля методов приложения, достижимых у Spark без тел JDK, среди достижимых с телами (E4, T5 документа `docs/ucfs-integration/ucfs-vs-spark.md`). Порог 50 % проходят шесть срезов: antlr, bloat, chart, fop, luindex и lusearch (столбец `covered` T2). Выводы о программах в этом документе относятся только к ним (интерпретация, E4 D14). Шесть непокрытых срезов — наблюдения о механике на малых графах. T2 даёт размеры входа UCFS: рёбра глобального PAG Spark, рёбра и поля графа UCFS и число пар ответа для обоих режимов связывания.

<!-- E5 table T2 -->
| bench | coverage % | covered | PAG edges | edges AN | fields AN | pairs AN | edges CG | fields CG | pairs CG |
|---|---|---|---|---|---|---|---|---|---|
| antlr | 95.8 | yes | 66989 | 112938 | 301 | 399466 | - | - | - |
| bloat | 53.8 | yes | 55029 | 92310 | 489 | 202310 | - | - | - |
| chart | 74.0 | yes | 60002 | 100984 | 676 | 305824 | 87584 | 676 | 347388 |
| eclipse | 37.2 | no | 35363 | 61334 | 425 | 68807 | 58390 | 425 | 211620 |
| fop | 99.3 | yes | 17732 | 33708 | 161 | 16494 | 30558 | 161 | 18509 |
| luindex | 73.9 | yes | 11968 | 21302 | 194 | 11985 | 21362 | 194 | 14496 |
| lusearch | 92.4 | yes | 20526 | 35672 | 314 | 28238 | 35356 | 314 | 38118 |
| pmd | 14.1 | no | 8736 | 16318 | 107 | 7430 | 16352 | 107 | 8177 |
| xalan | 1.9 | no | 2438 | 4508 | 33 | 1739 | 4496 | 33 | 1742 |
| checkstyle | 35.1 | no | 38730 | 65418 | 288 | 90675 | 50504 | 288 | 529296 |
| findbugs | 23.8 | no | 37388 | 62746 | 545 | 45334 | 62252 | 545 | 73044 |
| JPC | 16.2 | no | 13061 | 22394 | 254 | 12962 | 21558 | 254 | 17482 |

Машина и JVM (T1, D7, D15). Это ВМ Cloud.ru `gen-8-64` с 8 vCPU с долей 100 % (E5.md D7), процессор по `lscpu` — Intel Xeon Cascade Lake, ОС `Ubuntu 24.04.5 LTS`, JVM `Temurin 21.0.12.1+1`, сжатые указатели при `-Xmx16g` включены. Это та же JVM, что на машине разработки (E5.md D7). Других процессов `java` перед прогонами не было (`other-java` 0). ВМ прожила 4.90 ч от создания до удаления, и все части прогона шли на ней одна за другой (проверено: `docs/ucfs-integration/e5-results/vm-run.tsv`). ВМ развернул `scripts/ucfs/e5-vm-setup.sh`, части прогона выполнил `scripts/ucfs/e5-full.sh` (раздел 8).

<!-- E5 table T1 -->
| key | value |
|---|---|
| host-kind | vm |
| flavor | gen-8-64 |
| cpu-model | Intel Xeon Processor (Cascadelake) |
| cpu-count | 8 |
| mem-total-mb | 64303 |
| kernel | 6.8.0-139-generic |
| os | Ubuntu 24.04.5 LTS |
| java-version | OpenJDK Runtime Environment Temurin-21.0.12.1+1 (build 21.0.12.1+1-LTS) |
| jvm-flags | -XX:+ExitOnOutOfMemoryError |
| java-tool-options | - |
| java-options | - |
| jdk-java-options | - |
| xmx | 16g |
| compressed-oops | true |
| timeout | 900 |
| reps | 10 |
| warmup | 1 |
| skip | antlr:ucfs-CALL_GRAPH bloat:ucfs-CALL_GRAPH checkstyle:ucfs-CALL_GRAPH |
| other-java | 0 |
| git-head | af18519beba9b2c433ef8ca83ebc00fe65191239 |
| started | 2026-10-26T13:19:27+03:00 |
| finished | 2026-10-26T14:22:27+03:00 |

## 2. Время: UCFS против Spark

Три времени T3. «Spark» — строка `Time (sec)` оценщика Qilin в отдельном прогоне `-pta=insens`: секундомер оценщика стоит вокруг вызова `pureRun()` (`qilin.pta/src/qilin/pta/tools/BasePTA.java:64-66#pureRun`, `qilin.core/src/qilin/stat/SimplifiedEvaluator.java:62-70#stopwatch`). «kernel» — ядро Spark внутри прогона `-pta=ucfs`: `UcfsPTA.pureRun` сначала вызывает `super.pureRun()`, и время этого вызова печатается как `#UCFS-import-spark-ms` (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:155-168#pureRun`). «UCFS» — `#UCFS-import-ucfs-ms`, то есть экспорт PAG, грамматика, решатель и импорт ответа, в той же JVM сразу после ядра (там же). Значит, `-pta=ucfs` — это Spark плюс UCFS: UCFS работает после Spark на его PAG, и стоимость интеграции — kernel вместе с UCFS, а не UCFS вместо Spark.

Почему время Spark и время UCFS — разная работа. Внутри `pureRun` Spark решатель для каждого нового достижимого метода строит его MethodPAG (`qilin.core/src/qilin/core/solver/Solver.java:126-134#getMethodPAG`). `PAG.getMethodPAG` берёт тело метода через `PTAUtils.getMethodBody`, а тот при первом обращении вызывает `retrieveActiveBody`, то есть Soot строит Jimple метода (`qilin.core/src/qilin/core/pag/PAG.java:528-532#getMethodBody`, `qilin.core/src/qilin/util/PTAUtils.java:819-825#retrieveActiveBody`). Граф вызовов строится на лету в том же цикле: диспетчеризация мест вызова по новым points-to и обработка новых достижимых методов (`qilin.core/src/qilin/core/solver/Solver.java:114-122#virtualCallDispatch`). UCFS получает готовый глобальный PAG ядра, а в ANALYSIS ещё и рёбра «семян», которые решатель Spark записал из своих множеств (E4 D15, раздел 2 `docs/ucfs-integration/ucfs-vs-spark.md`). Поэтому отношение UCFS/Spark меньше 1 не значит, что UCFS быстрее решает ту же задачу: оно сравнивает решение на готовом графе с построением графа вместе с решением (интерпретация по коду выше). Отдельного таймера построения тел нет: он потребовал бы правки самого Spark (E5.md D2).

Доля ответа, поданная Spark. Столбец `seeded %` — доля пар SAME, которые по прогонам E4 неподвижная точка на том же графе теряет без семян Spark в `this`, в переменные исключений и в параметр `Finalizer.register` (E4 T6, `lost % (all)`). В ANALYSIS наименьшая доля у chart, 20.6 %, наибольшая у antlr, 91.9 %. Время UCFS в ANALYSIS — это время решения графа, в котором значительная часть ответа уже подана Spark (E4.md «Следствие для E5»). CALL_GRAPH — режим, где pts(`this`) считает UCFS: экспорт заменяет семена `this` рёбрами «получатель → `this`» по графу вызовов Spark (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:155-159#receiverAssigns`). Доля семян в этом режиме ниже, чем в ANALYSIS, на каждом бенчмарке, где она есть: наименьшая у chart в CALL_GRAPH, 4.5 %, наибольшая у findbugs в CALL_GRAPH, 26.6 % (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T3`).

Как читать столбцы. `covered` повторяет T2: выводы о программах — по строкам `yes`. `n` — число замеров со статусом ok. `UCFS/Spark` — медиана парных отношений и её интервал. `kernel/Spark` — контроль: ядро внутри `-pta=ucfs` делает ту же работу, что отдельный прогон Spark, поэтому отношение их медиан должно быть около 1 (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:155-158#pureRun`). Ядро и UCFS-часть идут в одной JVM друг за другом, а Spark — в отдельной JVM того же повтора. Стены `wall insens s` и `wall ucfs s` включают ещё старт JVM, загрузку классов Soot и оценщик Qilin.

<!-- E5 table T3 -->
| bench | binding | covered | seeded % | n | Spark ms | kernel ms | UCFS ms | UCFS/Spark | kernel/Spark | wall insens s | wall ucfs s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| antlr | ANALYSIS | yes | 91.9 | 10 | 3340 [3326, 3377] | 3344 | 130324 [117742, 140157] | 38.75 [35.30, 41.85] | 1.00 | 4.68 | 135.15 |
| antlr | CALL_GRAPH | yes | - | 0 | 3340 [3326, 3377] | skipped | - | - | - | 4.68 | - |
| bloat | ANALYSIS | yes | 88.7 | 10 | 2840 [2738, 2882] | 2815 | 13384 [12167, 14896] | 4.68 [4.29, 5.19] | 0.99 | 4.00 | 17.37 |
| bloat | CALL_GRAPH | yes | - | 0 | 2840 [2738, 2882] | skipped | - | - | - | 4.00 | - |
| chart | ANALYSIS | yes | 20.6 | 10 | 3417 [3368, 3466] | 3447 | 10180 [10017, 10447] | 2.97 [2.90, 3.19] | 1.01 | 5.13 | 15.30 |
| chart | CALL_GRAPH | yes | 4.5 | 10 | 3417 [3368, 3466] | 3452 | 23814 [23222, 24681] | 6.91 [6.76, 7.24] | 1.01 | 5.13 | 29.04 |
| eclipse | ANALYSIS | no | 78.2 | 10 | 2381 [2335, 2438] | 2377 | 1484 [1422, 1559] | 0.61 [0.60, 0.66] | 1.00 | 5.02 | 6.49 |
| eclipse | CALL_GRAPH | no | 21.1 | 10 | 2381 [2335, 2438] | 2398 | 37473 [35170, 40453] | 15.79 [14.43, 17.09] | 1.01 | 5.02 | 42.56 |
| fop | ANALYSIS | yes | 51.5 | 10 | 997 [976, 1008] | 996 | 409 [377, 495] | 0.41 [0.38, 0.50] | 1.00 | 2.62 | 3.06 |
| fop | CALL_GRAPH | yes | 9.0 | 10 | 997 [976, 1008] | 1002 | 538 [462, 545] | 0.54 [0.45, 0.55] | 1.00 | 2.62 | 3.12 |
| luindex | ANALYSIS | yes | 64.9 | 10 | 1268 [1240, 1289] | 1294 | 370 [326, 394] | 0.29 [0.26, 0.32] | 1.02 | 2.33 | 2.67 |
| luindex | CALL_GRAPH | yes | 22.0 | 10 | 1268 [1240, 1289] | 1288 | 572 [479, 615] | 0.45 [0.39, 0.47] | 1.02 | 2.33 | 2.88 |
| lusearch | ANALYSIS | yes | 75.3 | 10 | 1927 [1872, 1967] | 1906 | 788 [667, 852] | 0.41 [0.35, 0.44] | 0.99 | 3.02 | 3.77 |
| lusearch | CALL_GRAPH | yes | 21.0 | 10 | 1927 [1872, 1967] | 1898 | 2126 [2091, 2246] | 1.12 [1.06, 1.19] | 0.98 | 3.02 | 5.16 |
| pmd | ANALYSIS | no | 63.9 | 10 | 720 [689, 751] | 729 | 224 [211, 237] | 0.31 [0.29, 0.35] | 1.01 | 2.28 | 2.46 |
| pmd | CALL_GRAPH | no | 24.5 | 10 | 720 [689, 751] | 728 | 294 [280, 304] | 0.41 [0.39, 0.42] | 1.01 | 2.28 | 2.51 |
| xalan | ANALYSIS | no | 61.0 | 10 | 282 [279, 313] | 290 | 84 [81, 85] | 0.29 [0.27, 0.30] | 1.03 | 1.81 | 1.92 |
| xalan | CALL_GRAPH | no | 24.1 | 10 | 282 [279, 313] | 293 | 88 [86, 89] | 0.30 [0.28, 0.32] | 1.04 | 1.81 | 1.90 |
| checkstyle | ANALYSIS | no | 69.0 | 10 | 1940 [1896, 1988] | 1928 | 2165 [2106, 2249] | 1.11 [1.08, 1.15] | 0.99 | 3.71 | 5.96 |
| checkstyle | CALL_GRAPH | no | 12.1 | 0 | 1940 [1896, 1988] | skipped | - | - | - | 3.71 | - |
| findbugs | ANALYSIS | no | 69.8 | 10 | 2301 [2273, 2362] | 2294 | 1118 [1067, 1189] | 0.49 [0.47, 0.52] | 1.00 | 3.84 | 4.96 |
| findbugs | CALL_GRAPH | no | 26.6 | 10 | 2301 [2273, 2362] | 2276 | 4297 [4192, 4433] | 1.87 [1.81, 1.95] | 0.99 | 3.84 | 8.13 |
| JPC | ANALYSIS | no | 57.3 | 10 | 1455 [1437, 1498] | 1439 | 362 [315, 443] | 0.25 [0.22, 0.32] | 0.99 | 2.41 | 2.75 |
| JPC | CALL_GRAPH | no | 14.0 | 10 | 1455 [1437, 1498] | 1480 | 589 [533, 663] | 0.40 [0.36, 0.46] | 1.02 | 2.41 | 3.00 |

Контроль ядра. Во всех 21 строке с замерами `kernel/Spark` лежит от 0.98 до 1.04, внутри допуска [0.67, 1.5] проверки результатов (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T3`). Значит, ядро внутри `-pta=ucfs` и отдельный Spark на этой машине тратят почти одинаковое время, и отношение UCFS/Spark можно читать как «UCFS-часть в единицах `pureRun` Spark» (интерпретация).

Покрытые срезы, ANALYSIS. На antlr UCFS-часть медленнее Spark в 38.75 раза: медиана UCFS 130324 мс с интервалом [117742, 140157] против Spark 3340 мс. На bloat UCFS-часть медленнее Spark в 4.68 раза: UCFS 13384 мс против Spark 2840 мс. На chart в ANALYSIS UCFS-часть медленнее Spark в 2.97 раза: UCFS 10180 мс против Spark 3417 мс. На fop в ANALYSIS UCFS-часть занимает 409 мс при Spark 997 мс, отношение 0.41 [0.38, 0.50]. На luindex в ANALYSIS UCFS-часть занимает 370 мс при Spark 1268 мс, отношение 0.29 [0.26, 0.32]. На lusearch в ANALYSIS UCFS-часть занимает 788 мс при Spark 1927 мс, отношение 0.41 [0.35, 0.44]. Для трёх последних срезов действует оговорка выше: отношение UCFS/Spark меньше 1 не значит, что UCFS быстрее решает ту же задачу.

Покрытые срезы, CALL_GRAPH. На chart в CALL_GRAPH UCFS-часть медленнее Spark в 6.91 раза: UCFS 23814 мс против Spark 3417 мс. На lusearch в CALL_GRAPH UCFS-часть медленнее Spark в 1.12 раза, интервал отношения [1.06, 1.19]. На fop в CALL_GRAPH отношение 0.54 [0.45, 0.55], на luindex в CALL_GRAPH отношение 0.45 [0.39, 0.47]. Для antlr и bloat CALL_GRAPH в повторах нет (skipped), их пробы — в разделе 6.

Что видно по строкам T3. Интервал отношения UCFS/Spark не содержит 1 ни в одной строке с замерами, так что направление различия в каждой строке устойчиво к разбросу (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T3`). Отношение выше 1 у трёх покрытых срезов с самыми большими PAG, antlr, chart и bloat, а у fop, luindex и lusearch с PAG из 17732, 11968 и 20526 рёбер в ANALYSIS оно ниже 1 (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T2 T3`). Одного размера PAG мало, чтобы предсказать время: antlr и chart близки по числу рёбер (66989 и 60002), а время UCFS в ANALYSIS у antlr больше на порядок при большем числе пар ответа (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T2 T3`). На каждом бенчмарке, где есть оба режима, отношение в CALL_GRAPH выше, чем в ANALYSIS, и пар ответа в CALL_GRAPH больше при числе рёбер графа того же порядка (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T2 T3`). Интерпретация: в CALL_GRAPH UCFS сам выводит pts(`this`) без фильтра диспетчеризации, ответ растёт, и вместе с ним растёт работа GLL.

Непокрытые срезы — наблюдения о механике. На eclipse в ANALYSIS отношение 0.61, а на eclipse в CALL_GRAPH 15.79. На checkstyle в ANALYSIS UCFS-часть медленнее Spark в 1.11 раза. На findbugs в CALL_GRAPH UCFS-часть медленнее Spark в 1.87 раза. Это срезы с покрытием ниже 50 %, о программах eclipse, checkstyle и findbugs они ничего не говорят. CALL_GRAPH checkstyle в повторах нет (skipped), его проба — в разделе 6.

## 3. Время UCFS по фазам

Фазы (E5-S1) делят UCFS-часть на смежные интервалы, границы — чтения `System.nanoTime`, так что фазы в сумме дают `total` (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:159-175#phases`):
- `export` — `PagExport.export`, перевод глобального PAG ядра в граф UCFS (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:159-161#export`).
- `grammar` — `new PointsToGrammar(k)` для `k` полей графа и вход в `UcfsPointsTo.solve` до его первого оператора (`qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsPointsTo.kt:69-71#PhaseMarks`).
- `rsm` — сборка RSM грамматики (`grammar.rsm`, в UCFS @ `bd1c111` она ленивая и здесь вызывается явно) вместе с первым входом в `UcfsSolver` (`qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsSolver.kt:136-138#rsm`).
- `input` — входной граф UCFS и его стартовые вершины-объекты (`qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsSolver.kt:139-140#inputGraph`).
- `parse` — `Gll.gll(rsm, graph).parse()`, работа GLL (`qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsSolver.kt:141-142#parse`).
- `roots` — корни SPPF в пары вершин, `pairs` — пары вершин в отображение «переменная → объекты» (`qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsPointsTo.kt:72-80#pairs`).
- `import` — импорт ответа в виды UCFS и UCFS_TYPED (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:164-165#importAnswer`).

T4 — медианы фаз в мс и медиана доли `parse` в `total`.

<!-- E5 table T4 -->
| bench | binding | n | export | grammar | rsm | input | parse | roots | pairs | import | total | parse % |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| antlr | ANALYSIS | 10 | 112.5 | 7.4 | 63.6 | 48.2 | 129670.8 | 182.1 | 103.2 | 65.9 | 130323.9 | 99.6 |
| antlr | CALL_GRAPH | 0 | skipped | - | - | - | - | - | - | - | - | - |
| bloat | ANALYSIS | 10 | 103.6 | 8.3 | 126.1 | 49.9 | 12834.3 | 96.0 | 53.2 | 49.6 | 13384.6 | 96.2 |
| bloat | CALL_GRAPH | 0 | skipped | - | - | - | - | - | - | - | - | - |
| chart | ANALYSIS | 10 | 108.8 | 9.3 | 153.4 | 50.3 | 9599.9 | 144.3 | 62.2 | 60.5 | 10180.6 | 94.2 |
| chart | CALL_GRAPH | 10 | 145.7 | 9.2 | 145.3 | 50.0 | 23163.9 | 172.3 | 75.0 | 69.0 | 23813.5 | 97.2 |
| eclipse | ANALYSIS | 10 | 77.8 | 8.2 | 86.3 | 40.0 | 1173.2 | 40.3 | 27.7 | 27.3 | 1483.3 | 79.0 |
| eclipse | CALL_GRAPH | 10 | 105.7 | 8.1 | 91.3 | 38.8 | 37031.5 | 101.6 | 51.4 | 49.9 | 37472.8 | 98.8 |
| fop | ANALYSIS | 10 | 45.1 | 6.7 | 43.1 | 24.5 | 261.7 | 9.5 | 7.5 | 10.6 | 408.7 | 64.0 |
| fop | CALL_GRAPH | 10 | 61.4 | 6.7 | 43.1 | 23.2 | 369.8 | 10.3 | 7.6 | 11.8 | 538.7 | 68.5 |
| luindex | ANALYSIS | 10 | 31.7 | 6.9 | 53.9 | 17.1 | 240.7 | 7.0 | 5.3 | 7.3 | 370.6 | 64.9 |
| luindex | CALL_GRAPH | 10 | 44.9 | 6.8 | 54.2 | 16.9 | 424.8 | 8.2 | 5.8 | 8.9 | 571.3 | 74.3 |
| lusearch | ANALYSIS | 10 | 48.4 | 7.5 | 98.0 | 26.9 | 574.5 | 15.5 | 10.7 | 14.3 | 787.7 | 72.6 |
| lusearch | CALL_GRAPH | 10 | 65.9 | 7.2 | 88.7 | 25.8 | 1903.3 | 20.6 | 13.6 | 18.0 | 2126.1 | 89.0 |
| pmd | ANALYSIS | 10 | 25.7 | 6.3 | 31.3 | 13.4 | 134.6 | 4.5 | 3.5 | 5.1 | 224.1 | 59.6 |
| pmd | CALL_GRAPH | 10 | 37.3 | 6.2 | 31.4 | 13.3 | 193.0 | 4.6 | 3.6 | 5.4 | 294.5 | 65.3 |
| xalan | ANALYSIS | 10 | 13.3 | 5.6 | 17.2 | 5.2 | 38.9 | 1.1 | 0.9 | 1.3 | 83.6 | 46.2 |
| xalan | CALL_GRAPH | 10 | 17.7 | 5.6 | 16.7 | 5.1 | 39.5 | 1.2 | 0.9 | 1.4 | 88.0 | 45.0 |
| checkstyle | ANALYSIS | 10 | 76.1 | 7.4 | 61.6 | 40.9 | 1859.1 | 48.1 | 32.1 | 35.6 | 2165.1 | 86.0 |
| checkstyle | CALL_GRAPH | 0 | skipped | - | - | - | - | - | - | - | - | - |
| findbugs | ANALYSIS | 10 | 79.8 | 8.9 | 105.4 | 41.8 | 801.5 | 25.4 | 19.2 | 24.4 | 1117.6 | 72.4 |
| findbugs | CALL_GRAPH | 10 | 111.6 | 8.8 | 118.1 | 43.0 | 3917.9 | 39.9 | 26.5 | 27.7 | 4297.1 | 91.2 |
| JPC | ANALYSIS | 10 | 33.2 | 7.0 | 57.9 | 16.7 | 218.9 | 7.4 | 5.3 | 7.9 | 362.2 | 61.6 |
| JPC | CALL_GRAPH | 10 | 44.5 | 7.0 | 58.6 | 16.8 | 441.4 | 10.2 | 6.9 | 9.9 | 588.9 | 75.0 |

Где фаза доминирует. Утверждения о доминирующей фазе ниже относятся к строкам с `total` не меньше 5 s. На antlr, bloat и chart в ANALYSIS доминирует `parse`: у antlr 99.6 %, у bloat 96.2 %, у chart 94.2 % (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T4`). На chart и eclipse в CALL_GRAPH тоже доминирует `parse`: у chart 97.2 %, у eclipse 98.8 % (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T4`). Срез eclipse не покрыт, так что его строка — наблюдение о механике. На antlr в ANALYSIS остальные семь фаз вместе занимают меньше 1 s из 130323.9 мс (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T4`). Узкое место внутри `parse` E5 не мерил: профиль E4 указывал на `InputRange.equals` в `SppfStorage.addNode` UCFS (E4 D10).

Короткие UCFS-части. В остальных строках `total` меньше 5 s, у xalan в ANALYSIS это 83.6 мс при доле `parse` 46.2 %. На таких интервалах фазы показывают холодный старт: первую загрузку классов Kotlin и UCFS, интерпретатор до JIT, а не стоимость алгоритма, поэтому выводов о доминирующей фазе по ним нет (интерпретация).

Сборка RSM и число полей. В ANALYSIS медиана фазы `rsm` в целом растёт с числом полей графа (столбец `fields AN` T2), но не монотонно: xalan (33 поля) 17.2 мс, pmd (107 полей) 31.3 мс, fop (161 поле) 43.1 мс, luindex (194 поля) 53.9 мс, JPC (254 поля) 57.9 мс, checkstyle (288 полей) 61.6 мс, antlr (301 поле) 63.6 мс, lusearch (314 полей) 98.0 мс, eclipse (425 полей) 86.3 мс, bloat (489 полей) 126.1 мс, findbugs (545 полей) 105.4 мс, chart (676 полей) 153.4 мс (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T2 T4`). Это наблюдение, а не модель: RSM строится по грамматике `PointsToGrammar(k)`, которая зависит только от `k`, а остальное в фазе — разброс JVM (JIT, загрузка классов, GC) и первый вход в решатель (интерпретация). Фаза `rsm` начинается с создания `PhaseMarks` в `UcfsPointsTo.solve` и поэтому включает первый вход в `UcfsSolver`: загрузку и инициализацию его класса, создание лямбды и вызов (`qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsPointsTo.kt:69-71#reachablePairs`). Верификатор E5-S1 мерил эту добавку отдельно на машине разработки (тикет E5-S1, замечание R1), на ВМ её отдельно не мерили. На ВМ она не больше всей фазы `rsm` самого малого графа: у xalan в ANALYSIS медиана 17.2 мс, в CALL_GRAPH 16.7 мс. Поэтому на малых срезах `rsm` — верхняя оценка стоимости сборки RSM, а не сама эта стоимость (интерпретация).

Перестановки фаз нет. `export` — интервал вокруг `PagExport.export`, `parse` — интервал вокруг `Gll.parse()` (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:159-161#nExport`, `qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsSolver.kt:141-142#parse`), и в T4 `export` во всех строках с замерами меньше 150 мс, а `parse` больше 38 мс (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T4`).

## 4. Память

T6: пик RSS при `-Xmx16g` по GNU time (медиана и min–max), RSS анализа по оценке Qilin (`MemoryWatcher`, медиана), минимальная куча, кратность `16384/minheap` и приращение минимальной кучи UCFS-прогона к `insens` того же бенчмарка с точностью ±16 MB (шаг поиска 16 MB).

<!-- E5 table T6 -->
| bench | run | n | max RSS med MB | max RSS min-max | Qilin RSS med MB | min heap MB | 16384/minheap | min heap - insens MB |
|---|---|---|---|---|---|---|---|---|
| antlr | insens | 10 | 980 | 926-1217 | 966 | 143 | 114.6 | - |
| antlr | ucfs-ANALYSIS | 10 | 5803 | 5090-6211 | 5801 | 4271 | 3.8 | 4128 +-16 |
| antlr | ucfs-CALL_GRAPH | 0 | skipped | - | - | - | - | - |
| bloat | insens | 10 | 1272 | 1208-1313 | 1272 | 111 | 147.6 | - |
| bloat | ucfs-ANALYSIS | 10 | 2435 | 2285-2609 | 2432 | 1227 | 13.4 | 1116 +-16 |
| bloat | ucfs-CALL_GRAPH | 0 | skipped | - | - | - | - | - |
| chart | insens | 10 | 1692 | 1400-1713 | 1677 | 191 | 85.8 | - |
| chart | ucfs-ANALYSIS | 10 | 2828 | 2174-2882 | 2824 | 876 | 18.7 | 685 +-16 |
| chart | ucfs-CALL_GRAPH | 10 | 3517 | 2781-3987 | 3513 | 1785 | 9.2 | 1594 +-16 |
| eclipse | insens | 10 | 1590 | 1577-1607 | 1576 | - | - | - |
| eclipse | ucfs-ANALYSIS | 10 | 1928 | 1921-1946 | 1911 | - | - | - |
| eclipse | ucfs-CALL_GRAPH | 10 | 3990 | 3457-4670 | 3991 | - | - | - |
| fop | insens | 10 | 586 | 582-604 | 577 | 143 | 114.6 | - |
| fop | ucfs-ANALYSIS | 10 | 725 | 673-785 | 722 | 191 | 85.8 | 48 +-16 |
| fop | ucfs-CALL_GRAPH | 10 | 734 | 679-770 | 727 | 207 | 79.1 | 64 +-16 |
| luindex | insens | 10 | 673 | 661-679 | 661 | 79 | 207.4 | - |
| luindex | ucfs-ANALYSIS | 10 | 751 | 729-759 | 742 | 111 | 147.6 | 32 +-16 |
| luindex | ucfs-CALL_GRAPH | 10 | 798 | 781-805 | 791 | 127 | 129.0 | 48 +-16 |
| lusearch | insens | 10 | 916 | 835-955 | 908 | 79 | 207.4 | - |
| lusearch | ucfs-ANALYSIS | 10 | 1046 | 993-1088 | 1034 | 175 | 93.6 | 96 +-16 |
| lusearch | ucfs-CALL_GRAPH | 10 | 1678 | 1616-1761 | 1655 | 382 | 42.9 | 303 +-16 |
| pmd | insens | 10 | 526 | 503-540 | 519 | - | - | - |
| pmd | ucfs-ANALYSIS | 10 | 578 | 557-584 | 566 | - | - | - |
| pmd | ucfs-CALL_GRAPH | 10 | 598 | 584-607 | 590 | - | - | - |
| xalan | insens | 10 | 460 | 447-468 | 451 | - | - | - |
| xalan | ucfs-ANALYSIS | 10 | 480 | 476-496 | 474 | - | - | - |
| xalan | ucfs-CALL_GRAPH | 10 | 484 | 469-505 | 474 | - | - | - |
| checkstyle | insens | 10 | 994 | 983-1013 | 981 | - | - | - |
| checkstyle | ucfs-ANALYSIS | 10 | 1340 | 1296-1712 | 1330 | - | - | - |
| checkstyle | ucfs-CALL_GRAPH | 0 | skipped | - | - | - | - | - |
| findbugs | insens | 10 | 1068 | 972-1073 | 1063 | - | - | - |
| findbugs | ucfs-ANALYSIS | 10 | 1248 | 1239-1352 | 1240 | - | - | - |
| findbugs | ucfs-CALL_GRAPH | 10 | 2192 | 2139-2261 | 2172 | - | - | - |
| JPC | insens | 10 | 535 | 514-682 | 527 | - | - | - |
| JPC | ucfs-ANALYSIS | 10 | 609 | 557-631 | 593 | - | - | - |
| JPC | ucfs-CALL_GRAPH | 10 | 672 | 628-706 | 668 | - | - | - |

Минимальная куча. Все 16 поисков на шести покрытых срезах кончились статусом ok, то есть оба подтверждающих шага сошлись, статусов unconfirmed, error и le-lo нет (проверено: `docs/ucfs-integration/e5-results/minheap/minheap.tsv`). Для шести непокрытых срезов минимальную кучу не искали (D3), в T6 у них стоит «-».

Приращение кучи UCFS. На antlr приращение ucfs-ANALYSIS 4128 ±16 MB при минимальной куче 4271 MB, у insens 143 MB. На bloat приращение ucfs-ANALYSIS 1116 ±16 MB при минимальной куче 1227 MB, у insens 111 MB. На chart ucfs-ANALYSIS требует 876 MB, приращение 685 ±16 MB, а chart ucfs-CALL_GRAPH требует 1785 MB, приращение 1594 ±16 MB. На lusearch приращение ucfs-ANALYSIS 96 ±16 MB, а у lusearch ucfs-CALL_GRAPH 303 ±16 MB. На fop приращение ucfs-ANALYSIS 48 ±16 MB, у fop ucfs-CALL_GRAPH 64 ±16 MB. На luindex приращение ucfs-ANALYSIS 32 ±16 MB, у luindex ucfs-CALL_GRAPH 48 ±16 MB. Разностей меньше 32 MB, то есть в пределах шага поиска, в T6 нет. Оба процесса держат PAG Spark, поэтому приращение — память UCFS-части сверх ядра (интерпретация, D3). На antlr, bloat и chart прогон `-pta=ucfs` (Spark и UCFS) требует больше памяти, чем прогон Spark: приращение 4128, 1116 и 685 MB в ANALYSIS (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T6`).

Кратность кучи прогонов. На antlr в ucfs-ANALYSIS кратность фиксированной кучи прогонов `-Xmx16g` к минимальной — лишь 3.8, меньше четырёх (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T6`). По `Blackburn2025Rethinking` (страница 2, рисунок 1) затраты сборщика растут по мере того, как доступная куча сжимается к минимальной, а рекомендация H2 (страница 5) — задавать кучу кратной минимальной. Значит, время antlr в ANALYSIS при `-Xmx16g` может включать заметную долю работы GC, которой при большей куче не было бы (интерпретация: время GC отдельно не мерили, D13). У остальных строк T6 кратность не меньше 9.2 (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T6`).

RSS. Пик RSS при `-Xmx16g` — верхняя оценка следа процесса при этой настройке, а не потребность анализа. Он включает не только живые объекты, но и кучу, которую G1 занял и не вернул, а также память вне кучи: метаданные классов, код JIT, структуры сборщика (интерпретация, D3). Например, у antlr в ucfs-ANALYSIS медиана пика RSS 5803 MB при минимальной куче 4271 MB, а у luindex insens медиана пика RSS 673 MB при минимальной куче 79 MB. На непокрытых срезах RSS — единственная мера памяти: у eclipse в ucfs-CALL_GRAPH медиана 3990 MB, у eclipse insens 1590 MB.

## 5. Разброс времени и ответа

T5: разброс стены и времени анализа (для `insens` — `pureRun` Spark, для ucfs-прогонов — UCFS-часть), а также описательные помехи машины по прогонам со статусом ok.

<!-- E5 table T5 -->
| bench | run | n | wall med s | wall min | wall max | wall IQR | wall CV % | time med ms | time min | time max | time IQR | time CV % | max load1 | max other java | max steal % |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| antlr | insens | 10 | 4.68 | 4.62 | 4.79 | 0.07 | 1.1 | 3340 | 3308 | 3396 | 35 | 0.8 | 3.90 | 0 | 0.03 |
| antlr | ucfs-ANALYSIS | 10 | 135.15 | 116.51 | 162.89 | 13.83 | 9.2 | 130324 | 111673 | 158058 | 13876 | 9.5 | 3.91 | 0 | 0.01 |
| antlr | ucfs-CALL_GRAPH | 0 | skipped | - | - | - | - | - | - | - | - | - | - | - | - |
| bloat | insens | 10 | 4.00 | 3.92 | 4.08 | 0.07 | 1.2 | 2840 | 2716 | 2898 | 86 | 2.1 | 2.07 | 0 | 0.03 |
| bloat | ucfs-ANALYSIS | 10 | 17.37 | 16.05 | 19.23 | 2.30 | 6.6 | 13384 | 12062 | 15150 | 2422 | 8.8 | 2.07 | 0 | 0.05 |
| bloat | ucfs-CALL_GRAPH | 0 | skipped | - | - | - | - | - | - | - | - | - | - | - | - |
| chart | insens | 10 | 5.13 | 4.96 | 5.29 | 0.08 | 1.7 | 3417 | 3259 | 3488 | 56 | 1.8 | 2.33 | 0 | 0.03 |
| chart | ucfs-ANALYSIS | 10 | 15.30 | 14.96 | 16.24 | 0.31 | 2.2 | 10180 | 9758 | 11024 | 279 | 3.1 | 2.32 | 0 | 0.03 |
| chart | ucfs-CALL_GRAPH | 10 | 29.04 | 28.48 | 30.59 | 0.73 | 2.2 | 23814 | 23056 | 25236 | 813 | 2.8 | 2.68 | 0 | 0.01 |
| eclipse | insens | 10 | 5.02 | 4.84 | 5.16 | 0.11 | 1.7 | 2381 | 2320 | 2509 | 54 | 2.2 | 2.38 | 0 | 0.03 |
| eclipse | ucfs-ANALYSIS | 10 | 6.49 | 6.36 | 6.77 | 0.12 | 1.7 | 1484 | 1409 | 1574 | 106 | 3.9 | 2.59 | 0 | 0.07 |
| eclipse | ucfs-CALL_GRAPH | 10 | 42.56 | 40.19 | 46.25 | 3.58 | 5.1 | 37473 | 35133 | 41431 | 3738 | 6.1 | 2.87 | 0 | 0.01 |
| fop | insens | 10 | 2.62 | 2.54 | 2.70 | 0.06 | 1.8 | 997 | 974 | 1058 | 22 | 2.3 | 2.86 | 0 | 0.09 |
| fop | ucfs-ANALYSIS | 10 | 3.06 | 2.93 | 3.21 | 0.13 | 2.8 | 409 | 374 | 533 | 104 | 13.0 | 3.03 | 0 | 0.16 |
| fop | ucfs-CALL_GRAPH | 10 | 3.12 | 2.93 | 3.27 | 0.12 | 3.4 | 538 | 441 | 555 | 56 | 7.4 | 2.68 | 0 | 0.04 |
| luindex | insens | 10 | 2.33 | 2.28 | 2.43 | 0.05 | 1.9 | 1268 | 1235 | 1313 | 39 | 1.9 | 3.11 | 0 | 0.05 |
| luindex | ucfs-ANALYSIS | 10 | 2.67 | 2.61 | 2.81 | 0.10 | 2.3 | 370 | 309 | 414 | 58 | 9.3 | 3.11 | 0 | 0.09 |
| luindex | ucfs-CALL_GRAPH | 10 | 2.88 | 2.80 | 2.98 | 0.07 | 2.0 | 572 | 460 | 629 | 79 | 9.9 | 3.03 | 0 | 0.04 |
| lusearch | insens | 10 | 3.02 | 2.94 | 3.12 | 0.07 | 1.7 | 1927 | 1872 | 1981 | 71 | 2.0 | 3.32 | 0 | 0.08 |
| lusearch | ucfs-ANALYSIS | 10 | 3.77 | 3.60 | 3.93 | 0.19 | 3.0 | 788 | 651 | 857 | 141 | 10.0 | 3.38 | 0 | 0.03 |
| lusearch | ucfs-CALL_GRAPH | 10 | 5.16 | 5.01 | 5.37 | 0.17 | 2.4 | 2126 | 2021 | 2261 | 116 | 3.4 | 3.26 | 0 | 0.07 |
| pmd | insens | 10 | 2.28 | 2.16 | 2.34 | 0.14 | 3.1 | 720 | 679 | 755 | 36 | 3.4 | 3.91 | 0 | 0.06 |
| pmd | ucfs-ANALYSIS | 10 | 2.46 | 2.40 | 2.64 | 0.06 | 2.8 | 224 | 210 | 277 | 20 | 8.2 | 3.91 | 0 | 0.19 |
| pmd | ucfs-CALL_GRAPH | 10 | 2.51 | 2.44 | 2.64 | 0.06 | 2.3 | 294 | 271 | 317 | 14 | 4.2 | 3.38 | 0 | 0.05 |
| xalan | insens | 10 | 1.81 | 1.71 | 1.87 | 0.05 | 2.4 | 282 | 277 | 326 | 13 | 5.4 | 3.76 | 0 | 0.07 |
| xalan | ucfs-ANALYSIS | 10 | 1.92 | 1.86 | 1.95 | 0.06 | 1.7 | 84 | 80 | 87 | 3 | 2.5 | 3.78 | 0 | 0.19 |
| xalan | ucfs-CALL_GRAPH | 10 | 1.90 | 1.82 | 1.96 | 0.06 | 2.2 | 88 | 83 | 89 | 3 | 2.2 | 3.76 | 0 | 0.19 |
| checkstyle | insens | 10 | 3.71 | 3.64 | 3.81 | 0.08 | 1.4 | 1940 | 1873 | 2006 | 65 | 2.1 | 3.78 | 0 | 0.03 |
| checkstyle | ucfs-ANALYSIS | 10 | 5.96 | 5.73 | 6.11 | 0.08 | 1.8 | 2165 | 2076 | 2273 | 72 | 2.7 | 3.79 | 0 | 0.04 |
| checkstyle | ucfs-CALL_GRAPH | 0 | skipped | - | - | - | - | - | - | - | - | - | - | - | - |
| findbugs | insens | 10 | 3.84 | 3.70 | 3.96 | 0.07 | 1.7 | 2301 | 2178 | 2385 | 39 | 2.3 | 4.05 | 0 | 0.06 |
| findbugs | ucfs-ANALYSIS | 10 | 4.96 | 4.83 | 5.09 | 0.06 | 1.4 | 1118 | 1047 | 1222 | 56 | 4.5 | 3.65 | 0 | 0.05 |
| findbugs | ucfs-CALL_GRAPH | 10 | 8.13 | 7.96 | 8.31 | 0.14 | 1.2 | 4297 | 4173 | 4466 | 151 | 2.2 | 3.81 | 0 | 0.02 |
| JPC | insens | 10 | 2.41 | 2.35 | 2.47 | 0.07 | 1.7 | 1455 | 1397 | 1514 | 28 | 2.1 | 4.20 | 0 | 0.16 |
| JPC | ucfs-ANALYSIS | 10 | 2.75 | 2.62 | 2.85 | 0.09 | 2.6 | 362 | 293 | 478 | 57 | 14.3 | 4.05 | 0 | 0.05 |
| JPC | ucfs-CALL_GRAPH | 10 | 3.00 | 2.85 | 3.10 | 0.09 | 2.7 | 589 | 482 | 707 | 111 | 11.3 | 4.05 | 0 | 0.04 |

Время Spark. У insens CV времени анализа — от 0.8 % у antlr до 5.4 % у xalan (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T5`).

Шумные прогоны. Самый большой относительный разброс у коротких UCFS-частей: у JPC в ucfs-ANALYSIS CV 14.3 % при медиане 362 мс, у fop в ucfs-ANALYSIS CV 13.0 % при медиане 409 мс (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T5`). Среди длинных UCFS-частей шумнее всех antlr в ucfs-ANALYSIS: время от 111673 до 158058 мс, IQR 13876 мс, CV 9.5 % (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T5`). У antlr в ucfs-ANALYSIS также самый большой CV стены, 9.2 %. Возможная причина — сборщик мусора: у antlr в ucfs-ANALYSIS кратность кучи к минимальной лишь 3.8 (интерпретация, раздел 4). Интервалы медианы в T3 учитывают этот разброс.

Помехи. Столбец `max load1` — минутное среднее нагрузки перед прогоном, в него входит и прогон, закончившийся перед ним. Значения `max load1` лежат от 2.07 у bloat до 4.20 у JPC insens (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T5`). Других процессов `java` перед прогонами не было: `max other java` 0 во всех строках (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T5`). Доля `steal` времени CPU за прогон не превышала 0.19 % (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T5`). По этим двум столбцам соседи по хосту на замеры заметно не влияли (интерпретация).

Стабильность ответа. В T7 у insens 11 ключей ответа (метрики Qilin и рёбра PAG), у ucfs-прогонов 15 (ещё режим связывания и числа пар). T7 показывает, сколько ключей принимают больше одного значения за повторы и сколько в каждом повторе равны значению E4.

<!-- E5 table T7 -->
| bench | run | n | answer keys | varying | = E4 in every rep |
|---|---|---|---|---|---|
| antlr | insens | 10 | 11 | 0 | 11 of 11 |
| antlr | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| antlr | ucfs-CALL_GRAPH | 0 | skipped | - | - |
| bloat | insens | 10 | 11 | 0 | 11 of 11 |
| bloat | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| bloat | ucfs-CALL_GRAPH | 0 | skipped | - | - |
| chart | insens | 10 | 11 | 0 | 11 of 11 |
| chart | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| chart | ucfs-CALL_GRAPH | 10 | 15 | 0 | 15 of 15 |
| eclipse | insens | 10 | 11 | 0 | 11 of 11 |
| eclipse | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| eclipse | ucfs-CALL_GRAPH | 10 | 15 | 0 | 15 of 15 |
| fop | insens | 10 | 11 | 0 | 11 of 11 |
| fop | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| fop | ucfs-CALL_GRAPH | 10 | 15 | 0 | 15 of 15 |
| luindex | insens | 10 | 11 | 0 | 11 of 11 |
| luindex | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| luindex | ucfs-CALL_GRAPH | 10 | 15 | 0 | 15 of 15 |
| lusearch | insens | 10 | 11 | 0 | 11 of 11 |
| lusearch | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| lusearch | ucfs-CALL_GRAPH | 10 | 15 | 0 | 15 of 15 |
| pmd | insens | 10 | 11 | 0 | 11 of 11 |
| pmd | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| pmd | ucfs-CALL_GRAPH | 10 | 15 | 0 | 15 of 15 |
| xalan | insens | 10 | 11 | 0 | 11 of 11 |
| xalan | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| xalan | ucfs-CALL_GRAPH | 10 | 15 | 0 | 15 of 15 |
| checkstyle | insens | 10 | 11 | 0 | 11 of 11 |
| checkstyle | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| checkstyle | ucfs-CALL_GRAPH | 0 | skipped | - | - |
| findbugs | insens | 10 | 11 | 0 | 11 of 11 |
| findbugs | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| findbugs | ucfs-CALL_GRAPH | 10 | 15 | 0 | 15 of 15 |
| JPC | insens | 10 | 11 | 0 | 11 of 11 |
| JPC | ucfs-ANALYSIS | 10 | 15 | 0 | 15 of 15 |
| JPC | ucfs-CALL_GRAPH | 10 | 15 | 0 | 15 of 15 |

Меняющихся ключей ответа нет ни в одной строке: столбец `varying` равен 0, и в каждом повторе все ключи равны значениям E4 (проверено: `python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T7`). В E4 недетерминированными были ключи pts прогона `cov-JDK` с телами JDK (E5.md D6), а прогонов `cov-*` в E5 нет: покрытие взято из результатов E4.

## 6. Пробы за пределами бюджета

Пробы (D8) — по одному наблюдению на прогон, без повторов, с лимитом 3600 s и кучей `-Xmx52g`. Проба probe-cg — CALL_GRAPH antlr, bloat и checkstyle без тел JDK, проба probe-jdk — luindex с телами JDK в insens и ucfs-ANALYSIS. Они отвечают на вопрос E4 m7: сколько времени и памяти нужно там, где E4 не получил ответа в своём лимите времени.

<!-- E5 table T8 -->
| probe | bench | run | status | wall s | max RSS MB | UCFS ms | UCFS pairs | xmx | compressed oops | timeout s | JDK bodies |
|---|---|---|---|---|---|---|---|---|---|---|---|
| probe-cg | antlr | ucfs-CALL_GRAPH | ok | 1361.72 | 44184 | 1355158 | 511164 | 52g | false | 3600 | no |
| probe-cg | bloat | ucfs-CALL_GRAPH | timeout | 3601.00 | 54737 | - | - | 52g | false | 3600 | no |
| probe-cg | checkstyle | ucfs-CALL_GRAPH | ok | 569.55 | 16419 | 565155 | 529296 | 52g | false | 3600 | no |
| probe-jdk | luindex | insens | ok | 12.00 | 3603 | - | - | 52g | false | 3600 | yes |
| probe-jdk | luindex | ucfs-ANALYSIS | oom | 3596.84 | 55083 | - | - | 52g | false | 3600 | yes |

Оговорка о сжатых указателях (D8). При `-Xmx52g` HotSpot выключает сжатые указатели (столбец `compressed oops` T8 — `false`, при `-Xmx16g` в T1 — `true`). Объекты занимают больше памяти, поэтому «не хватило 52g» не значит «нужно больше 52g в настройке основного прогона», и RSS проб нельзя сравнивать с T6 (интерпретация, D8).

probe-cg. antlr в CALL_GRAPH ответил: стена 1361.72 s, UCFS-часть 1355158 мс, пик RSS 44184 MB, 511164 пары. В E4 этот прогон не уложился в 900 s при `-Xmx16g`. Теперь известно, что при `-Xmx52g` без сжатых указателей ответ есть, и одно наблюдение времени — около 23 минут (проверено: `docs/ucfs-integration/e5-results/probe-cg/runs.tsv`). bloat в CALL_GRAPH завершился статусом timeout: нет ответа в бюджете 3600 s при `-Xmx52g`, пик RSS к остановке 54737 MB. Вопрос m7 для bloat в CALL_GRAPH остаётся открытым, граница сдвинута с 900 до 3600 s. checkstyle в CALL_GRAPH ответил за 569.55 s при UCFS-части 565155 мс и пике RSS 16419 MB, а число пар 529296 совпало с E4 (T2, `pairs CG`). В основные повторы checkstyle в CALL_GRAPH не вошёл заранее, по оценке риска 900 s (D4), а не по результату.

probe-jdk. luindex insens с телами JDK завершился за 12.00 s с пиком RSS 3603 MB. luindex ucfs-ANALYSIS с телами JDK кончился статусом oom: JVM сама завершилась по OutOfMemoryError «Java heap space» через 3596.84 s при пике RSS 55083 MB (проверено: `docs/ucfs-integration/e5-results/probe-jdk/runs.tsv` и `out.txt` в `docs/ucfs-integration/e5-results/probe-jdk/raw.tar.xz`). Это не убийство извне: код выхода 3 даёт флаг `-XX:+ExitOnOutOfMemoryError`, а статуса killed нет ни у одного прогона и шага E5 (проверено: `docs/ucfs-integration/e5-results/bench/runs.tsv`, `docs/ucfs-integration/e5-results/minheap/steps.tsv`, `docs/ucfs-integration/e5-results/probe-cg/runs.tsv`, `docs/ucfs-integration/e5-results/probe-jdk/runs.tsv`). Секция `kernel-oom` файла `host.txt` — `unavailable`: без sudo журнал ядра на ВМ не читался (тикет E5-S5a). В какой фазе кончилась память, по выводу не видно: строки фаз печатаются после конца анализа (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:185-192#phaseLines`). Spark на luindex с телами JDK отработал весь прогон insens за 12.00 s, так что почти всё время пробы ucfs-ANALYSIS пришлось, вероятно, на UCFS-часть (интерпретация). В E4 эта проба остановилась по таймауту 540 s при `-Xmx16g` (проверено: `docs/ucfs-integration/e4-results/probe_jdk.txt`). Итог для m7: при `-Xmx52g` без сжатых указателей UCFS @ `bd1c111` на luindex с телами JDK ответа не дал, а сколько памяти нужно при сжатых указателях, проба не отвечает (D8).

## 7. Ограничения и угрозы валидности

- Срезы вместо программ. Без тел JDK вызовы в библиотеку не имеют эффекта, и граф бенчмарка — срез. Порог покрытия 50 % проходят шесть срезов из 12, выводы о программах относятся только к покрытым срезам (интерпретация, E4 D14). Непокрытые срезы, например xalan с покрытием 1.9 %, о программах DaCapo ничего не говорят. Сравнивать времена с опубликованными числами Qilin нельзя: `He2022Qilin` анализирует программы с полной библиотекой JDK (интерпретация, E4 D3).
- Время Spark включает построение тел методов. `pureRun` Spark строит Jimple, MethodPAG и граф вызовов, UCFS решает на готовом PAG, а в ANALYSIS ещё и с семенами Spark. Отношение UCFS/Spark меньше 1 не значит, что UCFS быстрее решает ту же задачу (интерпретация по коду раздела 2).
- Одна ВМ одного типа. Числа документа — наблюдения одной ВМ `gen-8-64` (`cpu-model` Cascade Lake, хотя API облака называет флейвор Broadwell, E5.md D7) в одном прогоне. Частотой CPU на ВМ управлять нельзя (D13). На другой машине абсолютные времена будут другими, переносить имеет смысл безразмерное отношение, и то с порогом ×2 (интерпретация, критерий 3 E5.md).
- Холодные JVM. JIT и загрузка классов входят во время. UCFS-часть идёт после ядра Spark в той же JVM, где код Soot и Qilin уже прогрет, а классы Kotlin и UCFS ещё нет (интерпретация, E5.md RS8). Сравнение «kernel» с «UCFS» внутри одной JVM поэтому не симметрично (интерпретация).
- `-ucfsseam` в прогонах. Подсчёт рёбер PAG идёт после анализа, вне `pureRun` (`qilin.pta/src/driver/Main.java:59-62#printEdgeCounts`), так что он входит в стену и RSS, но не во время анализа T3.
- UCFS без оптимизаций. Меряется UCFS @ `bd1c111` как есть (D12). Узкое место по профилю E4 — `InputRange.equals` в `SppfStorage.addNode` (E4 D10), кандидат на оптимизацию в E9. Времена `parse` из T4 — оценка этой версии, а не GLL вообще.
- Что решает UCFS на этом входе. Язык L_FT (`Sridharan2005Demand`) на этом графе задаёт контекстно-нечувствительный анализ Андерсена с учётом полей, записанный как CFL-достижимость (`Melski2000Interconvertibility`), то есть ту же задачу, что решает Spark, только без фильтров типа. Выигрыш UCFS — в общности решателя, а не в скорости (интерпретация, E4.md «Следствие для E5»).
- Память. Минимальная куча найдена с шагом 16 MB, разность двух поисков точна до ±16 MB. Минимальную кучу искали на шести покрытых срезах (D3). На antlr в ucfs-ANALYSIS кратность кучи прогонов к минимальной — лишь 3.8 (раздел 4), и время этого прогона может включать повышенную долю GC (интерпретация).
- Статистика. Проверок гипотез нет, интервалы медианы покрывают 97.9 % при 10 замерах (проверено: `acceptance/E5/e5tables.py:11-14#median_ci`). Время GC, частота CPU и память по фазам не мерились (D13).
- Пробы. Проба — одно наблюдение при `-Xmx52g` без сжатых указателей, её время и RSS несравнимы с повторами (раздел 6).
- Это не локальный прогон: `host-kind` в T1 — `vm`, запасной вариант E5.md D7 не понадобился.

## 8. Воспроизведение

Подготовка чистой ВМ `gen-8-64` с Ubuntu 24.04 (пакеты, закреплённые JDK, клон коммита прогона, `bootstrap.sh`, fat jar) и полный прогон четырьмя частями:

```
bash scripts/ucfs/e5-vm-setup.sh ~/e5 af18519beba9b2c433ef8ca83ebc00fe65191239
cd ~/e5/Qilin-AI-exp
env JAVA_HOME=~/e5/jdks/jdk-21.0.12.1+1 QILIN_JAR=~/e5/jar/Qilin-fat.jar E5_HOST_KIND=vm E5_FLAVOR=gen-8-64 \
    bash scripts/ucfs/e5-full.sh ~/e5/results
```

`e5-full.sh` по очереди запускает части `bench` (`scripts/ucfs/e5-bench.sh`), `minheap` (`scripts/ucfs/e5-minheap.sh`), `probe-cg` и `probe-jdk` и по окончании части пакует её сырые файлы в `<part>/raw.tar.xz`. ВМ готовит `e5-vm-setup.sh`, таблицы строит `e5tables.py`. Четыре части на ВМ заняли около 4.6 ч (проверено: `docs/ucfs-integration/e5-results/full.tsv`).

Таблицы и проверки на закоммиченных результатах:

```
python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results          # T1–T8
python3 acceptance/E5/e5tables.py docs/ucfs-integration/e5-results T3 T4    # отдельные таблицы
bash acceptance/E5/S5_results.sh       # результаты: машина, команды, согласованность времён, ответ = E4
bash acceptance/E5/S6_doc.sh           # механика этого документа
bash acceptance/E5/E5_repro.sh         # воспроизведение ответа и отношения UCFS/Spark на fop и lusearch, порог ×2
```

Сырые файлы прогонов (`cmd.txt`, `out.txt`, `time.txt` и др.) лежат в `docs/ucfs-integration/e5-results/<part>/raw.tar.xz`. Распаковка `tar -xJf` даёт каталоги `<bench>/<run>/rep<k>` (для минимальной кучи — шаги `s<step>-x<mb>`).
