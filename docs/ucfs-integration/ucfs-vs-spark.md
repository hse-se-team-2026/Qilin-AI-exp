# Сверка ответа UCFS со Spark на бенчмарках Qilin

Документ стори E4-S7 (эпик E4, пункт 4 плана AGENTS.md: импорт ответа UCFS в Qilin и сверка со Spark по метрикам). Числа взяты из закоммиченных результатов полного прогона `docs/ucfs-integration/e4-results/` (стори E4-S6, `git-head` `557de3d`). Таблицы T1–T6 — дословный вывод `python3 acceptance/E4/tables.py docs/ucfs-integration/e4-results`. Ссылка `путь:строка#символ` указывает на код Qilin-AI-exp на ветке этого документа; код путей `qilin.pta/src`, `qilin.core/src`, `qilin.ucfs/src` и `scripts/ucfs/e4-bench.sh` на ней совпадает с кодом `557de3d`, это сверяет `bash acceptance/E4/S6_results.sh`. Механику документа проверяет `bash acceptance/E4/S7_doc.sh`.

Слово «интерпретация» отмечает вывод автора, который код или результаты прямо не утверждают. Утверждение с пометкой о проверке называет команду, файл результатов или место в коде, которые его подтверждают.

Коротко:
- сравниваются три вида ответа одного прогона `-pta=ucfs`: SPARK (ядро Spark), UCFS (ответ GLL-решателя на экспортированном PAG) и UCFS_TYPED (ответ UCFS после однократного фильтра по типу узла переменной);
- конфигурация D3 (тела JDK исключены) анализирует срезы программ, а не программы DaCapo целиком: покрытие методов приложения выше порога 50 % у шести срезов из двенадцати (T5);
- метрики графа вызовов совпадают со Spark по построению, это не результат UCFS; один шаг диспетчеризации по ответу UCFS добавил бы рёбра на части программ (T4);
- MISSING = 0 и `#May Fail Cast` UCFS ≥ Spark — следствие построения; разница метрик — цена отсутствия фильтров типа в графе и грамматике, а не свойство GLL;
- `CALL_GRAPH` не уложился в 900 s на antlr и bloat, а с телами JDK UCFS не дал ответа в бюджете 540 s (раздел 6).

## 1. Постановка и конфигурация

Сравниваются два ответа на одном и том же PAG. Spark — контекстно-нечувствительный анализ Андерсена в Qilin (`-pta=insens`; Spark — `Lhotak2003Scaling`, Qilin — `He2022Qilin`). UCFS решает язык L_FT (`Sridharan2005Demand`, Fig. 3) на глобальном PAG, который Spark построил в том же прогоне; экспорт и грамматика описаны в `docs/ucfs-integration/ucfs-pointsto.md` (E3).

Прогон делает одна команда `bash scripts/ucfs/e4-bench.sh <каталог> antlr bloat chart eclipse fop luindex lusearch pmd xalan checkstyle findbugs JPC`. На каждом из 12 бенчмарков она запускает пять прогонов в отдельных JVM: `insens` (Spark), `ucfs-ANALYSIS` и `ucfs-CALL_GRAPH` (`-pta=ucfs -ucfsbinding=<режим> -ucfscompare -ucfspt`), `cov-D3` и `cov-JDK` (Spark с `-stats` без тел JDK и с ними; `scripts/ucfs/e4-bench.sh:162-167#ucfscompare`). Опции — стиль zipper `artifact/run.py` (`scripts/ucfs/e4-bench.sh:66#RUNPY_OPTS`), журнал рефлексии TamiFlex, `-libpath`, JRE `1.6.0_45`, а во всех прогонах, кроме `cov-JDK`, ещё `-exclude=java.*;javax.*;sun.*;com.sun.*;sunw.*;org.omg.*;org.w3c.*;org.xml.*;org.ietf.*;jdk.*` (`scripts/ucfs/e4-bench.sh:64#JDK_EXCLUDE`). Лимит прогона — 900 s, куча `-Xmx16g`. Файл `meta.tsv` результатов записывает команду, `git-head`, чистоту дерева и sha256 jar прогона.

Без тел JDK вызовы в библиотеку не имеют эффекта, и часть приложения становится недостижимой. Поэтому граф D3 — срез программы. Насколько срез покрывает приложение, меряет пара прогонов `cov-D3` и `cov-JDK`: покрытие — доля методов приложения, достижимых у Spark без тел JDK, среди методов приложения, достижимых с телами (`acceptance/E4/tables.py:148-157#coverage`). Spark с телами JDK здесь — наиболее полное доступное приближение программы (интерпретация, E4.md D14).

<!-- E4 table T5 -->
| bench | app methods D3 | app methods JDK | coverage % | covered | reachable D3 | reachable JDK | PAG edges D3 | PAG edges JDK | cov-JDK run |
|---|---|---|---|---|---|---|---|---|---|
| antlr | 1312 | 1369 | 95.8 | yes | 1746 | 8264 | 66989 | 548412 | 27.1 s, 2224 MB |
| bloat | 1346 | 2504 | 53.8 | yes | 1802 | 9531 | 55029 | 652254 | 28.5 s, 2385 MB |
| chart | 771 | 1042 | 74.0 | yes | 2436 | 16087 | 60002 | 1567759 | 49.0 s, 2696 MB |
| eclipse | 852 | 2293 | 37.2 | no | 1767 | 23517 | 35363 | 2755755 | 132.3 s, 4048 MB |
| fop | 971 | 978 | 99.3 | yes | 1360 | 8079 | 17732 | 535917 | 26.8 s, 2324 MB |
| luindex | 404 | 547 | 73.9 | yes | 805 | 7481 | 11968 | 459895 | 22.8 s, 1983 MB |
| lusearch | 866 | 937 | 92.4 | yes | 1333 | 8170 | 20526 | 495347 | 24.6 s, 2087 MB |
| pmd | 277 | 1971 | 14.1 | no | 603 | 12477 | 8736 | 736149 | 33.6 s, 2863 MB |
| xalan | 50 | 2604 | 1.9 | no | 268 | 10184 | 2438 | 650414 | 28.2 s, 2665 MB |
| checkstyle | 880 | 2506 | 35.1 | no | 1753 | 12876 | 38730 | 824598 | 36.5 s, 2664 MB |
| findbugs | 868 | 3640 | 23.8 | no | 2098 | 16869 | 37388 | 1094280 | 44.2 s, 3288 MB |
| JPC | 450 | 2777 | 16.2 | no | 987 | 16322 | 13061 | 1030700 | 44.1 s, 2803 MB |

Как читать T5. Порог покрытия 50 % проходят срезы antlr (95.8 %), bloat (53.8 %), chart (74.0 %), fop (99.3 %), luindex (73.9 %) и lusearch (92.4 %). Ниже порога остаются eclipse (37.2 %), checkstyle (35.1 %), findbugs (23.8 %), JPC (16.2 %), pmd (14.1 %) и xalan (1.9 %). Срез xalan содержит 50 методов приложения из 2604, достижимых с телами JDK, так что по нему нельзя судить о программе xalan. Выводы этого документа о бенчмарках относятся к шести покрытым срезам. Шесть непокрытых срезов показаны в таблицах как наблюдения о механике импорта и сверки, а не как результаты на программах DaCapo. Обе стороны сравнения работают на одном и том же PAG среза, поэтому сравнение UCFS со Spark на срезе корректно, а сравнение с опубликованными числами Qilin нет: `He2022Qilin` анализирует те же двенадцать программ с полной библиотекой `JDK1.6.0_45` (раздел 5 статьи; интерпретация, E4.md D3).

## 2. Импорт ответа UCFS в Qilin

`-pta=ucfs` создаёт анализ `UcfsPTA`, наследника `Spark` (`qilin.pta/src/driver/PTAFactory.java:48-49#UcfsPTA`). Его `pureRun()` сначала решает ядро Spark, затем экспортирует глобальный PAG в выбранном режиме связывания, запускает UCFS с `PointsToGrammar` на число полей графа и импортирует ответ (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:142-153#pureRun`). Импорт кладёт множества CI-объектов CI-переменных в два отображения: вид UCFS и вид UCFS_TYPED, где объект остаётся, только если `PTAUtils.castNeverFails` пропускает его в тип узла переменной (для узла приведения это тип приведения) (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:193-228#importAnswer`). Объект ROOT не импортируется, а пары с ним считаются отдельно (там же; строка `#UCFS-import-root-pairs`). Запросы `reachingObjects` в видах UCFS и UCFS_TYPED отвечают из этих отображений (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:308-340#reachingObjects`), поэтому метрики Qilin по ответу UCFS считает тот же код `SimplifiedEvaluator`, что и для Spark: он читает pts операнда приведения через `reachingObjects` (`qilin.core/src/qilin/stat/SimplifiedEvaluator.java:112-125#reachingObjects`). Ответ Spark остаётся в узлах PAG того же объекта, так что три вида сравниваются внутри одного прогона (E4.md D7, RS7: нумерация узлов между JVM различается).

Что импортировано: points-to каждой CI-переменной ответа UCFS, у которой есть объект кроме ROOT (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:193-228#importAnswer`). Ключи ответа — локальные переменные, в том числе узлы приведения и параметров с `this`, и глобальные переменные, то есть узлы статических полей и узлы строковых и классовых констант (`qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsPointsTo.kt:36-37#GlobalVarNode`; узлы глобальных переменных создаёт `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:317-341#makeGlobalVarNode`). Что осталось от Spark во всех видах:
- граф вызовов и достижимые методы: `UcfsPTA` не переопределяет `getCallGraph` и `getNakedReachableMethods` (Javadoc `qilin.pta/src/qilin/pta/tools/UcfsPTA.java:61-68#getCallGraph`);
- pts полей объектов: запрос узла `ContextField` уходит в Spark (`qilin.pta/src/qilin/pta/tools/UcfsPTA.java:317-323#ContextField`), потому что экспорт не передаёт UCFS рёбра узлов `o.f` (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:133-136#ContextField`);
- в режиме `ANALYSIS` ещё рёбра `new` «объект получателя → `this`», «объект исключения → переменная `catch` или узел броска» и «объект → параметр `Finalizer.register`»: их пишет решатель Qilin из множеств Spark (`qilin.core/src/qilin/core/builder/CallGraphBuilder.java:169-178#addVirtualEdge`, `qilin.core/src/qilin/core/builder/ExceptionHandler.java:76-104#dispatch`, `qilin.core/src/qilin/core/solver/Solver.java:229-241#handleImplicitCallToFinalizerRegister`), и экспорт оставляет их как есть (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:137-143#bindByCallGraph`). Значит, в `ANALYSIS` связывание `this` и потоки исключений приходят от Spark.

`CALL_GRAPH` — режим, где pts(`this`) считает UCFS. Экспорт выбрасывает рёбра `new` в `this` (кроме ребра от ROOT) и добавляет рёбра `assign` «переменная-получатель → `this` вызванного метода» по рёбрам графа вызовов Spark из записанных экземплярных мест вызова (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:155-159#receiverAssigns`, `qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:168-188#receiverAssigns`). Фильтра диспетчеризации у такого связывания нет (`qilin.ucfs/src/main/kotlin/qilin/ucfs/ReceiverBinding.kt:21-37#CALL_GRAPH`). Граф вызовов, рёбра аргументов и возвратов, рёбра исключений и ребро в `Finalizer.register` и в этом режиме — от Spark.

Почему метрики графа вызовов совпадают по построению. `#Reachable Method (CI)` и `#Call Edge(CI)` читают `getNakedReachableMethods()` и `getCallGraph()` (`qilin.core/src/qilin/stat/SimplifiedEvaluator.java:71-73#getCallGraph`), `#Virtual Call Site(Polymorphic)` считает цели мест вызова по тому же графу (`qilin.core/src/qilin/stat/SimplifiedEvaluator.java:90-101#edgesOutOf`). От вида ответа эти три метрики не зависят, поэтому их совпадение в трёх видах T2 — следствие кода, а не результат UCFS; механика документа проверяет его в каждом завершённом прогоне (`acceptance/E4/doc_check.py:147-152#Reachable`). Изменил бы ответ UCFS граф вызовов, меряет один шаг диспетчеризации (раздел 5): ноль новых рёбер означал бы, что граф Spark замкнут относительно ответа этого вида и итерация «pts → диспетчеризация → новый экспорт» остановилась бы на первом шаге, а ненулевое число — что ответ UCFS граф увеличил бы (интерпретация, E4.md D6).

Какая доля ответа UCFS подана Spark. «Семя» — ребро `new` экспортированного графа из объекта, отличного от ROOT, в `this` метода, в узел броска или переменную `catch`, или в параметр `Finalizer.register`; вид семени определяется по узлу-получателю (`qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:369-384#seedKind`). Счётчики T6 — число таких рёбер и число пар SAME, которые неподвижная точка без фильтров на том же графе находит без семян `this` и без всех семян (`qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:321-366#counters`). Независимый оракул счётчиков — `acceptance/E4/SeedCheck.java`: свой разбор `graph.dot` и `vertices.tsv` и своя неподвижная точка, без UCFS, без `qilin.ucfs` и без `UcfsCompare`; из сверки он берёт только строки SAME файла `pairs.tsv`, то есть какие пары считать (`acceptance/E4/SeedCheck.java:1-40#SeedCheck`).

<!-- E4 table T6 -->
| bench | binding | new edges | seeds this | seeds exception | seeds finalizer | SAME | SAME without this seeds | lost % (this) | SAME without seeds | lost % (all) |
|---|---|---|---|---|---|---|---|---|---|---|
| antlr | ANALYSIS | 15165 | 8442 | 3755 | 6 | 277590 | 46235 | 83.3 | 22472 | 91.9 |
| antlr | CALL_GRAPH | timeout | - | - | - | - | - | - | - | - |
| bloat | ANALYSIS | 18403 | 10426 | 5408 | 10 | 92413 | 37259 | 59.7 | 10443 | 88.7 |
| bloat | CALL_GRAPH | timeout | - | - | - | - | - | - | - | - |
| chart | ANALYSIS | 20125 | 12607 | 2707 | 26 | 266907 | 223071 | 16.4 | 211848 | 20.6 |
| chart | CALL_GRAPH | 7518 | 0 | 2707 | 26 | 266907 | 266907 | 0.0 | 254776 | 4.5 |
| eclipse | ANALYSIS | 10947 | 5379 | 3472 | 29 | 60210 | 24500 | 59.3 | 13103 | 78.2 |
| eclipse | CALL_GRAPH | 5568 | 0 | 3472 | 29 | 60210 | 60210 | 0.0 | 47490 | 21.1 |
| fop | ANALYSIS | 5613 | 3214 | 400 | 5 | 16419 | 9195 | 44.0 | 7963 | 51.5 |
| fop | CALL_GRAPH | 2399 | 0 | 400 | 5 | 16419 | 16419 | 0.0 | 14940 | 9.0 |
| luindex | ANALYSIS | 3168 | 1481 | 770 | 13 | 11007 | 6256 | 43.2 | 3858 | 64.9 |
| luindex | CALL_GRAPH | 1687 | 0 | 770 | 13 | 11007 | 11007 | 0.0 | 8580 | 22.0 |
| lusearch | ANALYSIS | 5367 | 2878 | 1313 | 14 | 24188 | 10138 | 58.1 | 5981 | 75.3 |
| lusearch | CALL_GRAPH | 2489 | 0 | 1313 | 14 | 24188 | 24188 | 0.0 | 19098 | 21.0 |
| pmd | ANALYSIS | 2258 | 1061 | 445 | 7 | 7392 | 4161 | 43.7 | 2672 | 63.9 |
| pmd | CALL_GRAPH | 1197 | 0 | 445 | 7 | 7392 | 7392 | 0.0 | 5580 | 24.5 |
| xalan | ANALYSIS | 678 | 308 | 143 | 6 | 1739 | 1098 | 36.9 | 679 | 61.0 |
| xalan | CALL_GRAPH | 370 | 0 | 143 | 6 | 1739 | 1739 | 0.0 | 1320 | 24.1 |
| checkstyle | ANALYSIS | 14943 | 10861 | 1931 | 40 | 65729 | 27723 | 57.8 | 20375 | 69.0 |
| checkstyle | CALL_GRAPH | 4082 | 0 | 1931 | 40 | 65729 | 65729 | 0.0 | 57781 | 12.1 |
| findbugs | ANALYSIS | 10129 | 4592 | 2572 | 13 | 38601 | 21598 | 44.0 | 11668 | 69.8 |
| findbugs | CALL_GRAPH | 5537 | 0 | 2572 | 13 | 38601 | 38601 | 0.0 | 28344 | 26.6 |
| JPC | ANALYSIS | 3456 | 1936 | 333 | 29 | 11100 | 6068 | 45.3 | 4745 | 57.3 |
| JPC | CALL_GRAPH | 1520 | 0 | 333 | 29 | 11100 | 11100 | 0.0 | 9549 | 14.0 |

Как читать T6. В режиме `ANALYSIS` без семян `this` теряется от 16.4 % (chart) до 83.3 % (antlr) пар SAME, без семян трёх видов — от 20.6 % (chart) до 91.9 % (antlr). На покрытых срезах потери без семян `this` такие: antlr 83.3 %, bloat 59.7 %, chart 16.4 %, fop 44.0 %, luindex 43.2 %, lusearch 58.1 %. Значит, на покрытых срезах, кроме chart, от 43.2 % (luindex) до 83.3 % (antlr) совпадения UCFS со Spark в `ANALYSIS` — ответ Spark о `this`, прошедший через UCFS, а не вывод UCFS, а на chart такая доля 16.4 % (интерпретация, E4.md D15). В режиме `CALL_GRAPH` семян `this` нет (столбец `seeds this` равен 0, а `SAME without this seeds` равен `SAME`): пары SAME, зависящие от связывания `this`, UCFS выводит сам. Без семян исключений и `Finalizer.register` в этом режиме теряется от 4.5 % (chart) до 26.6 % (findbugs) пар SAME; на покрытых срезах chart 4.5 %, fop 9.0 %, luindex 22.0 %, lusearch 21.0 %. Сравнение двух режимов на одном срезе: у luindex без семян трёх видов в `ANALYSIS` теряется 64.9 % пар SAME, а в `CALL_GRAPH` 22.0 %; у lusearch — 75.3 % и 21.0 %. Остаток в `CALL_GRAPH` — доля, которую Spark подаёт рёбрами исключений и `Finalizer.register`; граф вызовов при этом тоже остаётся от Spark (интерпретация).

## 3. Результаты

<!-- E4 table T1 -->
| bench | PAG edges | UCFS graph V/E/fields | insens | ucfs ANALYSIS | ucfs CALL_GRAPH |
|---|---|---|---|---|---|
| antlr | 66989 | 37257/112938/301 | 11.3 s, 1104 MB | 124.4 s, 6111 MB, UCFS 107242 ms | timeout (908.5 s, 17208 MB) |
| bloat | 55029 | 27460/92310/489 | 8.7 s, 1265 MB | 24.9 s, 2396 MB, UCFS 13510 ms | timeout (907.6 s, 17131 MB) |
| chart | 60002 | 33804/100984/676 | 13.0 s, 1258 MB | 26.3 s, 2259 MB, UCFS 11394 ms | 37.2 s, 3494 MB, UCFS 23270 ms |
| eclipse | 35363 | 21309/61334/425 | 11.6 s, 1275 MB | 17.5 s, 1396 MB, UCFS 2737 ms | 48.7 s, 3965 MB, UCFS 34823 ms |
| fop | 17732 | 13524/33708/161 | 5.2 s, 683 MB | 8.7 s, 792 MB, UCFS 948 ms | 8.9 s, 996 MB, UCFS 1417 ms |
| luindex | 11968 | 8424/21302/194 | 5.5 s, 680 MB | 7.6 s, 915 MB, UCFS 850 ms | 7.7 s, 891 MB, UCFS 962 ms |
| lusearch | 20526 | 13566/35672/314 | 7.0 s, 902 MB | 11.6 s, 941 MB, UCFS 1818 ms | 13.1 s, 1773 MB, UCFS 3735 ms |
| pmd | 8736 | 6844/16318/107 | 5.0 s, 640 MB | 7.2 s, 764 MB, UCFS 615 ms | 7.0 s, 808 MB, UCFS 725 ms |
| xalan | 2438 | 2119/4508/33 | 3.0 s, 523 MB | 4.9 s, 558 MB, UCFS 170 ms | 4.9 s, 562 MB, UCFS 200 ms |
| checkstyle | 38730 | 19229/65418/288 | 8.7 s, 1061 MB | 15.8 s, 1870 MB, UCFS 3887 ms | 443.4 s, 12035 MB, UCFS 431333 ms |
| findbugs | 37388 | 24082/62746/545 | 10.3 s, 1076 MB | 15.2 s, 1631 MB, UCFS 2275 ms | 17.8 s, 2318 MB, UCFS 6433 ms |
| JPC | 13061 | 9761/22394/254 | 4.6 s, 656 MB | 9.3 s, 892 MB, UCFS 1067 ms | 8.2 s, 908 MB, UCFS 1356 ms |

<!-- E4 table T2 -->
| bench | binding | reach | call edges | poly | may-fail S | may-fail U | may-fail T | avg pts S | avg pts U | avg pts T |
|---|---|---|---|---|---|---|---|---|---|---|
| antlr | ANALYSIS | 1746 | 20668 | 850 | 189 | 216 | 202 | 25.692 | 36.654 | 25.877 |
| antlr | CALL_GRAPH | timeout | - | - | - | - | - | - | - | - |
| bloat | ANALYSIS | 1802 | 11420 | 201 | 447 | 497 | 496 | 6.547 | 14.807 | 7.552 |
| bloat | CALL_GRAPH | timeout | - | - | - | - | - | - | - | - |
| chart | ANALYSIS | 2436 | 10407 | 150 | 167 | 188 | 185 | 10.166 | 12.775 | 10.247 |
| chart | CALL_GRAPH | 2436 | 10407 | 150 | 167 | 188 | 185 | 10.166 | 16.836 | 10.378 |
| eclipse | ANALYSIS | 1767 | 6996 | 147 | 71 | 71 | 71 | 6.324 | 7.332 | 6.395 |
| eclipse | CALL_GRAPH | 1767 | 6996 | 147 | 71 | 143 | 143 | 6.324 | 25.679 | 8.220 |
| fop | ANALYSIS | 1360 | 3786 | 83 | 6 | 6 | 6 | 2.748 | 2.758 | 2.748 |
| fop | CALL_GRAPH | 1360 | 3786 | 83 | 6 | 77 | 77 | 2.748 | 3.031 | 2.764 |
| luindex | ANALYSIS | 805 | 2819 | 138 | 11 | 11 | 11 | 2.576 | 2.892 | 2.585 |
| luindex | CALL_GRAPH | 805 | 2819 | 138 | 11 | 82 | 82 | 2.576 | 3.542 | 2.605 |
| lusearch | ANALYSIS | 1333 | 4639 | 303 | 57 | 67 | 67 | 3.449 | 4.101 | 3.493 |
| lusearch | CALL_GRAPH | 1333 | 4639 | 303 | 57 | 138 | 138 | 3.449 | 5.875 | 3.557 |
| pmd | ANALYSIS | 603 | 2350 | 12 | 4 | 4 | 4 | 2.493 | 2.498 | 2.493 |
| pmd | CALL_GRAPH | 603 | 2350 | 12 | 4 | 4 | 4 | 2.493 | 2.898 | 2.495 |
| xalan | ANALYSIS | 268 | 605 | 1 | 0 | 0 | 0 | 1.734 | 1.734 | 1.734 |
| xalan | CALL_GRAPH | 268 | 605 | 1 | 0 | 0 | 0 | 1.734 | 1.739 | 1.734 |
| checkstyle | ANALYSIS | 1753 | 6743 | 92 | 71 | 75 | 73 | 9.436 | 12.234 | 9.549 |
| checkstyle | CALL_GRAPH | 1753 | 6743 | 92 | 71 | 75 | 73 | 9.436 | 86.609 | 15.155 |
| findbugs | ANALYSIS | 2098 | 7107 | 114 | 51 | 52 | 52 | 3.052 | 3.797 | 3.102 |
| findbugs | CALL_GRAPH | 2098 | 7107 | 114 | 51 | 53 | 53 | 3.052 | 7.051 | 3.237 |
| JPC | ANALYSIS | 987 | 2962 | 17 | 30 | 31 | 31 | 2.754 | 3.146 | 2.763 |
| JPC | CALL_GRAPH | 987 | 2962 | 17 | 30 | 31 | 31 | 2.754 | 4.639 | 2.837 |

<!-- E4 table T3 -->
| bench | binding | Spark | UCFS | UCFS_TYPED | SAME | R3 | R4b | R1 | R2 | R5 | UNEXPLAINED | MISSING |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| antlr | ANALYSIS | 277590 | 399467 | 279442 | 277590 | 0 | 1 | 108086 | 13790 | 0 | 0 | 0 |
| antlr | CALL_GRAPH | timeout | - | - | - | - | - | - | - | - | - | - |
| bloat | ANALYSIS | 92413 | 202311 | 102801 | 92413 | 0 | 1 | 101675 | 8222 | 0 | 0 | 0 |
| bloat | CALL_GRAPH | timeout | - | - | - | - | - | - | - | - | - | - |
| chart | ANALYSIS | 266907 | 305825 | 267892 | 266907 | 0 | 1 | 34010 | 4907 | 0 | 0 | 0 |
| chart | CALL_GRAPH | 266907 | 347389 | 269214 | 266907 | 41564 | 1 | 34010 | 4907 | 0 | 0 | 0 |
| eclipse | ANALYSIS | 60210 | 68808 | 60740 | 60210 | 0 | 1 | 7759 | 838 | 0 | 0 | 0 |
| eclipse | CALL_GRAPH | 60210 | 211621 | 74042 | 60210 | 142813 | 1 | 7759 | 838 | 0 | 0 | 0 |
| fop | ANALYSIS | 16419 | 16495 | 16419 | 16419 | 0 | 1 | 48 | 27 | 0 | 0 | 0 |
| fop | CALL_GRAPH | 16419 | 18510 | 16482 | 16419 | 2015 | 1 | 48 | 27 | 0 | 0 | 0 |
| luindex | ANALYSIS | 11007 | 11986 | 11029 | 11007 | 0 | 1 | 925 | 53 | 0 | 0 | 0 |
| luindex | CALL_GRAPH | 11007 | 14497 | 11084 | 11007 | 2511 | 1 | 925 | 53 | 0 | 0 | 0 |
| lusearch | ANALYSIS | 24188 | 28239 | 24502 | 24188 | 0 | 1 | 3760 | 290 | 0 | 0 | 0 |
| lusearch | CALL_GRAPH | 24188 | 38119 | 24951 | 24188 | 9880 | 1 | 3760 | 290 | 0 | 0 | 0 |
| pmd | ANALYSIS | 7392 | 7431 | 7392 | 7392 | 0 | 1 | 31 | 7 | 0 | 0 | 0 |
| pmd | CALL_GRAPH | 7392 | 8178 | 7395 | 7392 | 747 | 1 | 31 | 7 | 0 | 0 | 0 |
| xalan | ANALYSIS | 1739 | 1740 | 1739 | 1739 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| xalan | CALL_GRAPH | 1739 | 1743 | 1739 | 1739 | 3 | 1 | 0 | 0 | 0 | 0 | 0 |
| checkstyle | ANALYSIS | 65729 | 90676 | 66437 | 65729 | 0 | 1 | 18394 | 6552 | 0 | 0 | 0 |
| checkstyle | CALL_GRAPH | 65729 | 529297 | 102190 | 65729 | 438621 | 1 | 18394 | 6552 | 0 | 0 | 0 |
| findbugs | ANALYSIS | 38601 | 45335 | 39017 | 38601 | 0 | 1 | 6316 | 417 | 0 | 0 | 0 |
| findbugs | CALL_GRAPH | 38601 | 73045 | 40141 | 38601 | 27710 | 1 | 6316 | 417 | 0 | 0 | 0 |
| JPC | ANALYSIS | 11100 | 12963 | 11128 | 11100 | 0 | 1 | 1390 | 472 | 0 | 0 | 0 |
| JPC | CALL_GRAPH | 11100 | 17483 | 11344 | 11100 | 4520 | 1 | 1390 | 472 | 0 | 0 | 0 |

T1 — размер графа и время, T2 — метрики Qilin по трём видам (S — SPARK, U — UCFS, T — UCFS_TYPED), T3 — пары (переменная, объект) с классами расхождения. В T3 столбец UCFS включает пару с ROOT, а в метрики T2 она не входит (раздел 4, R4b).

Исходы прогонов. `insens`, `ucfs-ANALYSIS`, `cov-D3` и `cov-JDK` завершились на всех 12 бенчмарках, `ucfs-CALL_GRAPH` — на десяти, на antlr и bloat он остановлен по лимиту 900 s (проверено: `docs/ucfs-integration/e4-results/runs.tsv`, столбцы `status` и `exit`). Завершённых ucfs-прогонов поэтому 22, о них и идёт речь ниже (проверено: `docs/ucfs-integration/e4-results/runs.tsv`).

MISSING = 0 во всех 22 завершённых прогонах — следствие построения, а не наблюдение о решателе (проверено: `python3 acceptance/E4/tables.py docs/ucfs-integration/e4-results T3`). UCFS решает неподвижную точку L_FT без фильтров на экспортированных рёбрах, а Spark — ту же неподвижную точку с фильтрами решателя Qilin, которые только не пускают объект в множество (`qilin.core/src/qilin/core/solver/Solver.java:319-339#propagatePTS`, `qilin.core/src/qilin/util/PTAUtils.java:349-354#addWithTypeFiltering`). Отсюда Spark ⊆ UCFS, если экспорт передал потоки Spark без потерь; наблюдением MISSING = 0 проверена именно эта полнота экспорта на двенадцати срезах (E4.md D16). Тем же построением объясняется `#May Fail Cast` U ≥ S: приведение считается непроходимым, если хотя бы один объект pts операнда не проходит `castNeverFails` (`qilin.core/src/qilin/stat/SimplifiedEvaluator.java:103-125#castNeverFails`), а pts операнда у UCFS содержит pts Spark. Вид UCFS_TYPED содержит Spark по той же причине: объект Spark прошёл фильтр типа переменной при распространении и проходит его в конце (интерпретация кода `importAnswer`).

Разница метрик T2 — эффект фильтров Spark, а не свойство GLL или UCFS. На проверочных входах приёмки (малые программы, pmd и luindex) ответ UCFS совпадает с независимой неподвижной точкой Андерсена без фильтров по тому же `graph.dot` (`acceptance/E4/AndersenCheck.java`; проверки `bash acceptance/E4/S2_cli_ucfs.sh`, `bash acceptance/E4/S3_compare.sh`, `bash acceptance/E4/S5_bench.sh`), так что решатель L_FT без типов на тех же рёбрах дал бы те же пары (интерпретация). Разница возникает потому, что в графе и грамматике нет фильтров по объявленному типу, по типу приведения и запрета обращений к пустому массиву, которые Spark применяет при распространении: фильтр типа — при добавлении объекта в множество узла, запрет пустого массива — на рёбрах store и load (`qilin.core/src/qilin/core/solver/Solver.java:254-275#disallowStoreOrLoadOn`). Пример на покрытом срезе bloat: `#May Fail Cast` 447 у Spark, 497 у UCFS и 496 у UCFS_TYPED, `#Avg Points-to` 6.547, 14.807 и 7.552. На покрытом срезе lusearch в `ANALYSIS` `#May Fail Cast` 57, 67 и 67, `#Avg Points-to` 3.449, 4.101 и 3.493. На fop и luindex в `ANALYSIS` `#May Fail Cast` трёх видов равны (6 и 11), а `#Avg Points-to` UCFS выше: 2.758 против 2.748 у fop и 2.892 против 2.576 у luindex.

`#Avg Points-to` U ≥ S — наблюдение, не следствие построения: знаменатель метрики — число переменных с непустым pts (`qilin.core/src/qilin/stat/SimplifiedEvaluator.java:165-186#varCntNoNative`), и переменная, пустая у Spark и непустая у UCFS, может уменьшить среднее. В 22 прогонах среднее UCFS ни разу не оказалось ниже Spark и совпало с ним на срезе xalan в `ANALYSIS` (1.734; проверено: `python3 acceptance/E4/tables.py docs/ucfs-integration/e4-results T2`).

UCFS_TYPED — фильтр по типу один раз в конце, а не на каждом узле. Он возвращает средний размер pts почти к Spark (bloat 7.552 против 6.547, UCFS 14.807), но не возвращает `#May Fail Cast` (bloat 496 против 447). У `Lhotak2003Scaling` удаление объектов несовместимого типа после анализа дало почти ту же точность, что фильтр по ходу анализа (Table II статьи); здесь это верно для среднего размера и неверно для приведений. Причина, вероятно, в том, что метрика приведений читает pts операнда приведения, объявленный тип которого часто `Object`, и фильтр в конце этот операнд не сужает (интерпретация).

В режиме `CALL_GRAPH` к лишним парам добавляется класс R3 (раздел 4). `#Avg Points-to` UCFS в `CALL_GRAPH` выше, чем в `ANALYSIS`, на каждом из десяти срезов, где завершились оба режима, а `#May Fail Cast` UCFS выше на eclipse, fop, luindex, lusearch и findbugs и равен на chart, pmd, xalan, checkstyle и JPC (проверено: `python3 acceptance/E4/tables.py docs/ucfs-integration/e4-results T2`). На fop `#May Fail Cast` UCFS 77 против 6 у Spark, на luindex 82 против 11, на lusearch 138 против 57. UCFS_TYPED здесь не уменьшает `#May Fail Cast` (у fop 77, у luindex 82, у lusearch 138), а средний размер возвращает почти к Spark: у lusearch 3.557 против 3.449. Самый большой рост среднего — у непокрытого среза checkstyle в `CALL_GRAPH`: 86.609 против 9.436 у Spark.

Число пар последней ступени эталона, где включены фильтры решателя, равно числу пар Spark в 22 завершённых прогонах (проверено: `bash acceptance/E4/S6_results.sh`, строка `finished ucfs runs checked`). Это проверка D5 (б) на масштабе бенчмарков, и совпадают в ней числа пар, а не множества. Равенство множеств отсюда следует вместе с UNEXPLAINED = 0 (раздел 4), если пары последней ступени есть и в ответе UCFS, то есть если ответ UCFS содержит неподвижную точку эталона без фильтров на экспорте `ANALYSIS` (интерпретация). В режиме `ANALYSIS` на входах приёмки это условие следует из проверки `AndersenCheck` (ответ UCFS равен неподвижной точке без фильтров по тому же `graph.dot`, выше), на остальных прогонах оно не проверялось.

## 4. Классы расхождений и примеры

Класс пары, которая есть у UCFS и нет у Spark, — первая ступень эталонной неподвижной точки, которая эту пару уже не держит; ступени включают фильтры решателя Qilin по одному (`qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:274-287#steps`, `qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:245-262#UNEXPLAINED`):
- R3 (только `CALL_GRAPH`): пары нет без фильтров на экспорте `ANALYSIS`, где pts(`this`) задаёт диспетчеризация решателя, а не переменная-получатель;
- R4b: объект ROOT невидим (номер 0 в `HybridPointsToSet`);
- R1: добавлены объявленные типы переменных, кроме узлов приведения, и узлов полей;
- R2: добавлены типы приведения у узлов приведения;
- R5: добавлен запрет store и load через пустой массив (`qilin.core/src/qilin/core/solver/Solver.java:341-346#disallowStoreOrLoadOn`);
- UNEXPLAINED: пару держит и последняя ступень;
- MISSING: пара есть у Spark и нет у UCFS.

Фильтры эталона вызывают те же функции, что решатель (`qilin.pta/src/qilin/pta/ucfs/ReferenceFixpoint.java:45-58#castNeverFails`). Порядок ступеней — соглашение: пара, которую убирают два фильтра поодиночке, получает класс более ранней ступени (E3.md D16, интерпретация). Пример ниже — строка `examples.tsv` и разбор одного вывода пары в неподвижной точке без фильтров по рёбрам экспортированного графа. Выводы найдены диагностическим обходом прогона той же конфигурации; он не входит в репозиторий, его файлы указаны в отчёте стори (`docs/ai/tickets/E4-S7.md`). Класс назначает код сверки; разбор показывает, на каком узле этого пути стоит фильтр, который убирает объект (интерпретация).

Счёт по T3. В `ANALYSIS` R4b равен 1 на каждом бенчмарке, R1 — от 0 (xalan) до 108086 (antlr), R2 — от 0 (xalan) до 13790 (antlr), R5 = 0. На срезе bloat пар класса R1 (101675) больше, чем пар Spark (92413). В `CALL_GRAPH` добавляется R3 — от 3 (xalan) до 438621 (checkstyle); R1 и R2 в двух режимах одинаковы. Ступени R4b..R5 в обоих режимах работают на экспорте `ANALYSIS` (`qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:274-287#analysis`), так что в `CALL_GRAPH` они классифицируют те пары ответа UCFS вне Spark, которые держит неподвижная точка без фильтров на экспорте `ANALYSIS`; равные счёты SAME, R4b, R1 и R2 двух режимов в T3 согласуются с тем, что ответ `CALL_GRAPH` содержит ответ `ANALYSIS`, но поштучно это не проверялось (интерпретация).

EXAMPLE luindex ucfs-ANALYSIS R1: `$stack1 <org.apache.lucene.index.IndexReader: org.apache.lucene.store.Directory directory()>` <- `new org.apache.lucene.index.SegmentReader in method <java.lang.Class: java.lang.Object newInstance0()>` — объект создан моделью рефлексии по журналу TamiFlex: в теле `Class.newInstance0()` все классы журнала выделяются в одну переменную `$stack17` типа `Object`. Без фильтров объект идёт по возврату `newInstance()` в `$stack22` метода `FSDirectory.getDirectory(File,boolean)`, через узел приведения `(FSDirectory) $stack22` в переменную `dir` типа `FSDirectory`, затем в параметр `d` конструктора `IndexWriter`, в поле `IndexWriter.directory`, поле `SegmentInfo.dir`, параметр `directory` метода `IndexReader.init` и поле `IndexReader.directory` объекта `SegmentReader`, откуда его читает `$stack1`. Spark отбросил бы `SegmentReader` уже на узле приведения к `FSDirectory`, а класс получился R1, а не R2: ступень R1 без фильтров приведения убирает объект на переменной `dir` с объявленным типом `FSDirectory` и на узлах полей типа `Directory` (интерпретация одного вывода).
EXAMPLE lusearch ucfs-ANALYSIS R1: `$stack1 <org.apache.lucene.index.FilterIndexReader: int maxDoc()>` <- `new org.apache.lucene.store.FSDirectory in method <java.lang.Class: java.lang.Object newInstance0()>` — тот же механизм рефлексии на другом бенчмарке: объект `FSDirectory` из `$stack17` метода `Class.newInstance0()` возвращается в `$stack14` типа `Object` метода `SegmentReader.get(Directory,SegmentInfo,SegmentInfos,boolean,boolean)`, проходит узел приведения `(SegmentReader) $stack14` в переменную `instance` с объявленным типом `SegmentReader`, дальше через возвраты `IndexReader$1.doBody()` и `IndexReader.open` в параметр `in` конструкторов `LusearchHarness$OneNormsReader` и `FilterIndexReader`, в поле `FilterIndexReader.in` и в `$stack1`. Фильтр Spark отбросил бы `FSDirectory` на приведении к `SegmentReader`; ступень R1 убирает его раньше ступени R2 на переменной `instance` типа `SegmentReader`, отсюда класс R1 (интерпретация одного вывода).
EXAMPLE luindex ucfs-ANALYSIS R2: `(org.apache.lucene.document.Field) stringValue#5 <org.apache.lucene.index.DocumentWriter: void invertDocument(org.apache.lucene.document.Document)>` <- `new java.io.StringReader in method <org.apache.lucene.index.DocumentWriter: void invertDocument(org.apache.lucene.document.Document)>` — поток внутри одного метода `DocumentWriter.invertDocument`: объект `StringReader` из `$stack50` копируется в локальную `stringValue#5` с объявленным типом `Object`, а затем в узел приведения `(Field) stringValue#5` с типом приведения `Field`. Объявленный тип `Object` объект пропускает, поэтому ступень R1 пару держит; фильтр приведения отвергает её, потому что `StringReader` не подтип `Field`, и так же объект не пустил бы в узел приведения Spark, отсюда класс R2.
EXAMPLE chart ucfs-ANALYSIS R2: `(com.lowagie.text.Anchor) l1 <com.lowagie.text.pdf.PdfDocument: boolean add(com.lowagie.text.Element)>` <- `new com.lowagie.text.Meta in method <com.lowagie.text.Document: boolean addCreationDate()>` — объект `Meta` из `$stack4` метода `Document.addCreationDate()` передаётся аргументом в параметр типа `Element` метода `PdfDocument.add(Element)` и копируется в `l1` того же типа; оба узла объект пропускают, потому что `Meta` реализует `Element`. Узел приведения `(Anchor) l1` с типом приведения `Anchor` объект `Meta` отвергает, и Spark его туда не кладёт; так как объявленные типы на пути пару не убирают, а тип приведения убирает, класс R2.
EXAMPLE luindex ucfs-CALL_GRAPH R3: `$r0 <sun.security.provider.Sun: void <init>()>` <- `new org.apache.lucene.index.SegmentReader in method <java.lang.Class: java.lang.Object newInstance0()>` — место вызова — оператор `specialinvoke $stack17.<sun.security.provider.Sun: void <init>()>()` модели рефлексии в `Class.newInstance0()`, где `$stack17` держит объекты всех классов журнала TamiFlex. В `CALL_GRAPH` экспорт добавляет по ребру графа вызовов Spark из этого места ребро `$stack17 -assign-> this` конструктора `Sun.<init>()`, и `this` получает все объекты `$stack17`, в том числе `SegmentReader`, а дальше через `l0` и узел приведения `(java.util.Map) $stack6` объект доходит до `$r0`. В `ANALYSIS` `this` конструктора получает только объекты, которые решатель диспетчеризовал в него, а для `specialinvoke` он оставляет цель, только если тип объекта совместим с классом цели (`qilin.core/src/qilin/core/builder/CallGraphBuilder.java:154-167#dispatch`), поэтому без связывания по переменной пары нет и класс R3.
EXAMPLE chart ucfs-CALL_GRAPH R3: `$stack1 <com.lowagie.text.pdf.BaseFont: java.lang.String getEncoding()>` <- `new com.lowagie.text.pdf.PdfFont in method <com.lowagie.text.pdf.PdfFont: com.lowagie.text.pdf.PdfFont getDefaultFont()>` — объект `PdfFont` без фильтров проходит через поле `PdfChunk.font`, возврат `PdfChunk.font()`, элемент массива `Object[]` метода `PdfDocument.flushLines()` и узел приведения `(String) $stack33` в `$stack36` метода `PdfDocument.writeLineToContent`, который служит получателем вызова `substring(int)`. Место вызова — `$stack36.substring(...)`: в `CALL_GRAPH` по ребру Spark в `String.substring(int)` добавлено ребро `$stack36 -assign-> this` этого метода, и `this` получает `PdfFont`, который решатель в `String.substring` не диспетчеризовал бы (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:155-159#receiverAssigns`); дальше объект идёт через возврат `substring`, который без контекста попадает ко всем местам вызова этого метода, в поле `BaseFont.encoding` объекта `TrueTypeFontUnicode` и в `$stack1`. В `ANALYSIS` `this` метода `String.substring` получает только объекты, которые решатель Spark туда диспетчеризовал, поэтому пары нет и класс R3.
EXAMPLE fop ucfs-ANALYSIS R4b: `Parm THIS_NODE to <FakeMain: void fakeMain()> <FakeMain: void fakeMain()>` <- `ROOT in method null` — ребро ROOT `-new->` `this` у `fakeMain` кладёт решатель при построении точки входа, а не по points-to; контекстный объект ROOT создаётся в конструкторе `PTA` без нумератора и получает номер 0, а малое множество `HybridPointsToSet` считает 0 пустой ячейкой. Поэтому Spark этой пары не показывает, UCFS её находит, импорт её не переносит в виды и считает в строке `#UCFS-import-root-pairs`, а сверка относит её к R4b: одна пара на прогон.

Места кода к примерам. Ребро «объект → `this`» по диспетчеризации решателя: `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:154-167#dispatch` (фильтр `canStoreType` для `specialinvoke`). ROOT: `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:134-139#getEntryPoints`, `qilin.core/src/qilin/core/PTA.java:61-67#rootNode`, `qilin.core/src/qilin/core/sets/HybridPointsToSet.java:132-146#forall`, `qilin.pta/src/qilin/pta/tools/UcfsPTA.java:193-228#roots`.

R5 на всех 22 прогонах бенчмарков пуст (проверено: `python3 acceptance/E4/tables.py docs/ucfs-integration/e4-results T3`). Ступень R5 с ненулевым результатом проверена только ручной программой `EmptyArrayProg`, где объект пишется в массив нулевой длины и читается из него (`acceptance/E4/prog/e4prog/EmptyArrayProg.java:24-35#empty`; проверка `bash acceptance/E4/S3_compare.sh`). На бенчмарках этот класс не встретился: при R5 = 0 и UNEXPLAINED = 0 после ступени R2 неклассифицированных пар не остаётся и классификация останавливается (`qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:245-262#pending`), а неподвижную точку со всеми фильтрами, включая запрет R5, сверка строит отдельно для числа пар последней ступени (`qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:353-355#lastPairs`), и это число равно числу пар Spark (раздел 3).

UNEXPLAINED = 0 во всех 22 итоговых прогонах (проверено: `python3 acceptance/E4/tables.py docs/ucfs-integration/e4-results T3`). История проверки эталона. Первый полный прогон (итерация 0 стори S6, `git-head` `2f09236`, ветка `ai/E4-S6-results`) дал на findbugs в обоих режимах UNEXPLAINED 103, R2 314 и число пар последней ступени 38704 при 38601 парах Spark (проверено: `git show 715dddd:docs/ucfs-integration/e4-results/values.tsv`, строки `findbugs ucfs-ANALYSIS` и `findbugs ucfs-CALL_GRAPH`). Проверка «число пар последней ступени = числу пар Spark» (D5 (б)) поймала дефект эталона, а не свойство входа: эталон кэшировал фильтры типов в `HashMap<Type,…>` по `equals`, а `FastHierarchy.canStoreType` Soot сравнивает супертип массива с `Object` по `==`, и два приведения метода `XmlParser.extendArray` с типом `WeakObjectType` получали фильтр канонического `Object` и пропускали массивы, которые решатель отбрасывает (E4-S6.md, «Oracle dispute check»). Стори E4-S3b заменила кэш на кэш по идентичности объекта типа (`qilin.pta/src/qilin/pta/ucfs/ReferenceFixpoint.java:97-98#filterByType`, объяснение — `qilin.pta/src/qilin/pta/ucfs/ReferenceFixpoint.java:63-73#WeakObjectType`) и добавила в приёмку ручную программу `WeakCastProg` с такими приведениями (`acceptance/E4/prog/e4prog/WeakCastProg.java:23-31#twoArrays`; проверка `bash acceptance/E4/S3b_weak_type.sh`). После исправления эти пары стали R2: в итоговых результатах у findbugs R2 = 417 и UNEXPLAINED = 0 в обоих режимах (T3). Значит, ветка UNEXPLAINED на итоговых результатах дала 0, а ненулевой результат наблюдался только на дефектном эталоне (проверено: `git show 715dddd:docs/ucfs-integration/e4-results/values.tsv` против `docs/ucfs-integration/e4-results/values.tsv`). Отличает ли она законную необъяснённую пару от ошибки эталона, держится на чтении кода (`qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:260-262#UNEXPLAINED`) и на сверке числа пар последней ступени со Spark (раздел 3).

## 5. Граф вызовов

Граф вызовов `-pta=ucfs` — граф Spark по построению (раздел 2), поэтому столбцы `reach`, `call edges` и `poly` в T2 одинаковы в трёх видах. Изменил бы его ответ UCFS, меряет один шаг диспетчеризации: каждое экземплярное место вызова, записанное решателем, диспетчеризуется по CI-объектам получателя в виде той же функцией `PTAUtils.dispatch` и с тем же фильтром `canStoreType` для `specialinvoke`, что у решателя, и пары (место, цель), которых нет в графе Spark у этого места, — новые рёбра (`qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:408-452#dispatch`, `qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:459-471#targets`; решатель — `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:154-167#dispatch`). Граф и множества анализа при этом не меняются.

<!-- E4 table T4 -->
| bench | binding | CG edges at sites | found over SPARK | new over UCFS | new over UCFS_TYPED | new over SPARK |
|---|---|---|---|---|---|---|
| antlr | ANALYSIS | 20059 | 20059 | 73 | 73 | 0 |
| antlr | CALL_GRAPH | timeout | - | - | - | - |
| bloat | ANALYSIS | 10787 | 10787 | 61 | 61 | 0 |
| bloat | CALL_GRAPH | timeout | - | - | - | - |
| chart | ANALYSIS | 9434 | 9434 | 13 | 13 | 0 |
| chart | CALL_GRAPH | 9434 | 9434 | 20 | 20 | 0 |
| eclipse | ANALYSIS | 5584 | 5584 | 8 | 8 | 0 |
| eclipse | CALL_GRAPH | 5584 | 5584 | 111 | 111 | 0 |
| fop | ANALYSIS | 3059 | 3059 | 0 | 0 | 0 |
| fop | CALL_GRAPH | 3059 | 3059 | 0 | 0 | 0 |
| luindex | ANALYSIS | 2462 | 2462 | 0 | 0 | 0 |
| luindex | CALL_GRAPH | 2462 | 2462 | 0 | 0 | 0 |
| lusearch | ANALYSIS | 4118 | 4118 | 0 | 0 | 0 |
| lusearch | CALL_GRAPH | 4118 | 4118 | 20 | 20 | 0 |
| pmd | ANALYSIS | 2101 | 2101 | 0 | 0 | 0 |
| pmd | CALL_GRAPH | 2101 | 2101 | 0 | 0 | 0 |
| xalan | ANALYSIS | 469 | 469 | 0 | 0 | 0 |
| xalan | CALL_GRAPH | 469 | 469 | 0 | 0 | 0 |
| checkstyle | ANALYSIS | 5478 | 5478 | 32 | 32 | 0 |
| checkstyle | CALL_GRAPH | 5478 | 5478 | 181 | 181 | 0 |
| findbugs | ANALYSIS | 6233 | 6233 | 2 | 2 | 0 |
| findbugs | CALL_GRAPH | 6233 | 6233 | 13 | 13 | 0 |
| JPC | ANALYSIS | 2086 | 2086 | 0 | 0 | 0 |
| JPC | CALL_GRAPH | 2086 | 2086 | 4 | 4 | 0 |

Как читать T4. В 22 завершённых прогонах диспетчеризация по объектам вида SPARK находит у записанных мест те же рёбра, что граф Spark: столбцы `CG edges at sites` и `found over SPARK` равны, а `new over SPARK` равен 0 (проверено: `python3 acceptance/E4/tables.py docs/ucfs-integration/e4-results T4`). Это проверка самой процедуры шага. Значит, объекты SAME у получателя дают только рёбра Spark, а новые рёбра дают объекты, которые у получателя есть у UCFS и нет у Spark (интерпретация). В `ANALYSIS` новые рёбра есть на antlr (73), bloat (61), chart (13), eclipse (8), checkstyle (32) и findbugs (2); на fop, luindex, lusearch, pmd, xalan и JPC их 0. В `CALL_GRAPH` новые рёбра есть на chart (20), eclipse (111), lusearch (20), checkstyle (181), findbugs (13) и JPC (4); на fop, luindex, pmd и xalan их 0. Из покрытых срезов в `ANALYSIS` новые рёбра дали antlr, bloat и chart, а fop, luindex и lusearch — нет. Число новых рёбер у UCFS_TYPED совпадает с UCFS в каждом прогоне (проверено: `python3 acceptance/E4/tables.py docs/ucfs-integration/e4-results T4`). Вероятная причина: объекты, дающие новые цели, проходят объявленный тип переменной-получателя; в `ANALYSIS` это объекты, которые Spark отбросил фильтром выше по пути, а в `CALL_GRAPH` к ним добавляются объекты класса R3, которые пришли к получателю через связывание `this` по переменной без фильтра диспетчеризации (интерпретация). Источник списков рёбер ниже — `sootOutput/ucfs-compare/dispatch.tsv` и `pairs.tsv` прогонов; каталог прогона пишет `bash scripts/ucfs/e4-bench.sh`, в `e4-results` эти файлы не входят.

DISPATCH antlr ANALYSIS: 73 новых рёбра дают в основном вызовы `el.getLabel()` в `genElementAST` генераторов `JavaCodeGenerator`, `CppCodeGenerator` и `CSharpCodeGenerator` и `e.getLabel()` в `mapTreeVariable`; новые цели — `AlternativeElement.getLabel`, `CharRangeElement.getLabel` и `RuleRefElement.getLabel`. У получателей этих мест UCFS кроме пар SAME держит пары класса R1 с объектами `ActionElement`, `BlockEndElement`, `CharRangeElement`, `RuleEndElement`, `RuleRefElement` и `TreeElement`, которые Spark отбросил выше по пути по объявленному типу, и их диспетчеризация даёт цели, которых у этих мест в графе Spark нет.
DISPATCH bloat ANALYSIS: 61 новое ребро приходится на вызовы `loop_2.contains`, `loop_2.iterator` и `outerLoop_2.addAll` в `FlowGraph.peelLoops` (цели `HashSet.contains`, `HashSet.iterator`, `AbstractCollection.addAll`), `a.type()` в `TBAA.canAlias`, `use.parent()` в `RegisterAllocator$IGNode.computeWeight` и вызовы `visit` в `SSAPRE` и `PrintVisitor`. В pts получателей этих мест у UCFS почти нет пар SAME, а есть пары класса R1, то есть объекты, которые Spark отбросил фильтром объявленного типа выше по пути; их типы и выбирают новые цели.
DISPATCH chart ANALYSIS: 13 новых рёбер — вызовы `l1.type()` в `Cell.addElement(Element)` с целями `Meta.type`, `Rectangle.type` и `Table.type`, вызовы `$stack22.alignment()` и `$stack22.widthPercentage()` там же и вызовы `getDimension`, `getElement` и `complete` в `Table.mergeInsertedTables` и `Table.insertTable`. У этих получателей у UCFS есть пары класса R1 с объектами `Meta`, `Rectangle`, `Table` и `Cell` и нет пар SAME, а у Spark их pts пусты, так что новые цели дают объекты, которые Spark отфильтровал по объявленному типу выше по пути.
DISPATCH chart CALL_GRAPH: 20 новых рёбер включают те же рёбра `Cell.addElement` и `Table.mergeInsertedTables` из объектов класса R1 и рёбра из объектов класса R3, например `l0.printStackTrace()` и `l0.getMessage()` в методах `Throwable` с целями `ExceptionConverter` и `DocumentException`, `l0.convertToBytes` в `BaseFont.getWidth` с целью `TrueTypeFontUnicode.convertToBytes` и `this.getDrawingSupplier()` в `AbstractRenderer`. Объекты R3 попали в `this` этих методов через рёбра «получатель → `this`» без фильтра диспетчеризации.
DISPATCH eclipse ANALYSIS: 8 новых рёбер дают вызовы `$stack53.toString()` и `$stack63.toString()` в `FilterImpl.toString` (цели `Long.toString` и `FilterImpl.toString`) и `$stack6.equals` в `Headers.getIndex` (цель `FilterImpl.equals`). У получателей `$stack53` и `$stack6` UCFS кроме пар SAME держит пары класса R1, а у `$stack63` пар SAME нет и pts Spark пуст, а пары UCFS — класса R1; это объекты `Long`, `FilterImpl`, строки и массивы, которые Spark отбросил по объявленному типу выше по пути.
DISPATCH eclipse CALL_GRAPH: 111 новых рёбер в основном дают вызов `$stack53.toString()` в `FilterImpl.toString` с целями `toString` многих классов OSGi и Eclipse и вызов `l0.hashCode()` внутри `Object.toString()` с целями `File.hashCode`, `Long.hashCode`, `String.hashCode` и другими. В `CALL_GRAPH` `this` метода `Object.toString()` получает pts получателей мест, которые Spark связал с этим методом, целиком, включая объекты классов со своим `toString` (класс R3), и их диспетчеризация по `hashCode` даёт новые цели.
DISPATCH lusearch CALL_GRAPH: 20 новых рёбер дают вызовы `this.doc()`, `this.score()` и `this.next()` в `Scorer.score` с целями `TermScorer`, `BooleanScorer` и `BooleanScorer2`, `weight.getValue()` в конструкторах `TermScorer` и `PhraseScorer` с целями весов `PhraseQuery`, `MultiPhraseQuery`, `BooleanQuery` и `TermQuery`, `this.getEnum` в `MultiTermQuery.rewrite` с целью `FuzzyQuery.getEnum`, а также `rewrittenQuery.rewrite` в `IndexSearcher.rewrite` и `query_1.clone()` в `BooleanQuery.rewrite`. Объекты этих получателей, дающие новые цели, — в основном пары класса R3: связывание `this` по переменной-получателю без фильтра диспетчеризации передало в `this` объекты других подклассов.
DISPATCH checkstyle ANALYSIS: 32 новых рёбра дают вызовы `value.toString()` в методах конвертеров `org.apache.commons.beanutils.converters` (`ClassConverter`, `URLConverter`, `StringConverter`, `NumberConverter`, `FileConverter` и других) с целями `AbstractCollection.toString` и `NaturalOrdering.toString`, а также `collection.size()` и `collection.iterator()` в `AbstractConverter.convertArray`. В pts получателей у UCFS есть пары класса R1 с объектами `ArrayList`, `NaturalOrdering` и `Integer`, которые Spark отбросил по объявленному типу выше по пути.
DISPATCH checkstyle CALL_GRAPH: 181 новое ребро включает вызовы `value.toString()` конвертеров `beanutils` с целями `toString` многих классов (`WeakHashtable`, `URI`, `Throwable`, `DetailAST`, `CommonToken` и других) и вызовы `listIterator` и `iterator` на `this` в `ImmutableList` Guava с целями `EmptyImmutableList`. Получатели держат пары классов R1 и R3, причём R3 преобладает: связывание `this` по переменной без фильтра диспетчеризации передаёт в `this` объекты других подклассов, и диспетчеризация по ним даёт цели, которых нет в графе Spark.
DISPATCH findbugs ANALYSIS: 2 новых ребра — вызов `l0.toString()` в `String.valueOf(Object)` с целью `Object.toString` и вызов `l1.equals` в `LinkedList.indexOf` с целью `Object.equals`. У этих получателей UCFS держит пары класса R1, среди которых объекты классов без своих `toString` и `equals`; Spark отбросил их по объявленному типу выше по пути, поэтому у него этих целей у мест нет.
DISPATCH findbugs CALL_GRAPH: 13 новых рёбер дают вызов `l0.hashCode()` в `Object.toString()` с целями `Constant.hashCode` из BCEL, `Vector.hashCode`, `AbstractList.hashCode`, `URL.hashCode`, `String.hashCode` и другими, вызовы `l0.toString()` в `String.valueOf` и `l1.equals` в `LinkedList.indexOf` с целями `Instruction` из BCEL и `l0.getMessage()` в `Throwable` с целью `SAXException.getMessage`. Основная часть объектов, дающих эти цели, — пары класса R3, полученные `this` методов `Object.toString` и `Throwable` без фильтра диспетчеризации.
DISPATCH JPC CALL_GRAPH: 4 новых ребра даёт один вызов `l0.hashCode()` внутри `Object.toString()` с целями `Enum.hashCode`, `Integer.hashCode`, `String.hashCode` и `ConstantPoolInfo.hashCode`. `this` метода `Object.toString()` в `CALL_GRAPH` получает pts получателей мест, связанных Spark с этим методом, целиком, включая объекты классов со своим `toString` (пары класса R3), и их диспетчеризация по `hashCode` даёт новые цели.

Что следует. Ответ UCFS в `ANALYSIS` увеличил бы граф вызовов Spark на трёх покрытых срезах из шести за счёт объектов, которые Spark отбросил фильтром типа, а в `CALL_GRAPH` — ещё за счёт связывания `this` без фильтра диспетчеризации (интерпретация, E4.md D6). Это один шаг, а не неподвижная точка. Рёбра аргументов и возврата решатель добавляет в PAG на каждое новое ребро своего графа вызовов (`qilin.core/src/qilin/core/builder/CallGraphBuilder.java:199-206#processCallAssign`, `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:227-267#processCallAssign`), поэтому у ребра, которого в графе Spark нет, их нет и в экспортированном графе, а у цели, которую Spark не достиг, нет и тела в PAG (`qilin.pta/src/qilin/pta/ucfs/UcfsCompare.java:91-102#Dispatch`). Часть новых целей Spark достиг через другие места вызова, и их тела в экспортированном графе есть (например, у chart в `ANALYSIS` — тело `Meta.type()`, цели нового ребра из `Cell.addElement`), но потоки через новое ребро без нового решения Qilin и нового экспорта не известны; итерация «pts UCFS → диспетчеризация → новый экспорт» в E4 не входит (E4.md D6). Ноль новых рёбер на fop, luindex и lusearch в `ANALYSIS` означает, что граф Spark на этих срезах замкнут относительно ответа UCFS и итерация остановилась бы на первом шаге (интерпретация).

## 6. Масштаб и ограничения

**Срез вместо программы.** Без тел JDK глобальный PAG — от 2438 (xalan) до 66989 (antlr) рёбер, а с телами JDK — от 459895 (luindex) до 2755755 (eclipse) рёбер (T5). Граф D3 — срез программы; покрыт порогом 50 % срез у шести бенчмарков из двенадцати (раздел 1). Выводы о бенчмарках относятся к покрытым срезам antlr, bloat, chart, fop, luindex и lusearch, с оговоркой, что библиотека без тел недоопределена. Срезы pmd (14.1 %) и xalan (1.9 %) не подаются как программы DaCapo pmd и xalan.

**`CALL_GRAPH` на больших срезах.** На antlr и bloat режим `CALL_GRAPH` остановлен по лимиту 900 s с пиком памяти 17208 MB и 17131 MB (T1), так что сравнить этот режим на двух покрытых срезах нельзя. Самый долгий из завершённых — checkstyle: 443.4 s и 12035 MB, из них UCFS 431333 ms, тогда как `ANALYSIS` на том же срезе занял 15.8 s (T1). Это результат, а не обход: исход `CALL_GRAPH` на больших программах не входит в критерий эпика.

**Проба с телами JDK.** `bash acceptance/E4/probe_jdk.sh` делает на luindex с телами JDK (без `-exclude`) два прогона. Первый — только Spark (`-pta=insens -ucfsseam`): по нему печатаются строки `PROBE seam:` о глобальном PAG, который экспортировал бы `-pta=ucfs`, потому что сам `-pta=ucfs` печатает их лишь после ответа UCFS (`acceptance/E4/probe_jdk.sh:7-8#ucfsseam`, `acceptance/E4/probe_jdk.sh:28-31#ucfsseam`). Второй — `-pta=ucfs` с лимитом 540 s и `-Xmx16g`, по нему печатается строка `PROBE finished=` (`acceptance/E4/probe_jdk.sh:33-42#finished`; вывод — `docs/ucfs-integration/e4-results/probe_jdk.txt`):

```
PROBE seam: #UCFS-seam-NEW: 202171
PROBE seam: #UCFS-seam-ASSIGN: 249106
PROBE seam: #UCFS-seam-LOAD: 4890
PROBE seam: #UCFS-seam-STORE: 3728
PROBE finished=no exit=124 wall_s=541 max_rss_mb=15156
```

UCFS @ `bd1c111` не дал ответа в бюджете 540 s на графе с телами JDK, а пик памяти к моменту остановки — 15156 MB (проверено: `docs/ucfs-integration/e4-results/probe_jdk.txt`). Сколько времени и памяти ему нужно на этом графе, неизвестно: проба показывает лишь, что ответа нет в бюджете. Поэтому сравнения со Spark с полной библиотекой в E4 нет.

**Время и память — одно наблюдение.** Числа времени и памяти в T1 и T5 — одно наблюдение одного прогона, полный прогон шёл параллельно с чужой JVM на той же машине (E4-S6.md, «Итерация 1»). Пример разброса: время UCFS на antlr в `ANALYSIS` (строка `UCFS-import-ucfs-ms`, экспорт, решение и импорт) — 107242 ms в итоговом прогоне и 139069 ms в итерации 0 с тем же кодом экспорта и решателя: между `git-head` двух итераций изменился только эталон сверки `ReferenceFixpoint.java`, который работает после замера (проверено: `git show 715dddd:docs/ucfs-integration/e4-results/values.tsv`; `git diff --stat 2f09236 557de3d -- qilin.pta/src qilin.core/src qilin.ucfs/src`). Разброс есть и у значений pts: в прогоне `cov-JDK` (Spark с телами JDK) значение `Local CS Pointer-to Relation` у chart было 7091081 в итерации 0 и 7090595 в итоговом прогоне, а метрики покрытия и графа вызовов у chart в двух итерациях совпали (проверено: `git show 715dddd:docs/ucfs-integration/e4-results/values.tsv` против `docs/ucfs-integration/e4-results/values.tsv`). В повторных запусках верификатора S6 на одном jar встречались оба значения, то есть значение меняется от запуска к запуску; причина до строки кода не установлена (E4-S6.md, «Verifier»; E9-backlog #40). Ключи pts прогона `cov-JDK` поэтому — одно наблюдение из возможных значений. T5 этим не затронута: её столбцы, кроме времени и памяти, в двух итерациях равны (проверено: `python3 acceptance/E4/tables.py <каталог> T5` на `runs.tsv` и `values.tsv` из `git show 715dddd:docs/ucfs-integration/e4-results/` против той же команды на `docs/ucfs-integration/e4-results`). Повторы и статистика времени — задача E5.

**Что ещё ограничивает выводы.**
- Проверены ядро `insens` и CI-проекция: другие шаблоны `-pta` дают проекцию своего графа, она здесь не сравнивалась (E3.md RS3).
- UCFS_TYPED — не Spark: фильтр в конце не равен фильтру на каждом шаге, разницу дают классы R1 и R2 выше по пути (раздел 3).
- Пары сравниваются внутри одного прогона: нумерация узлов между JVM различается (RS7, E4.md D7); между прогонами сравниваются числа, а примеры `examples.tsv` записаны строками узлов без номеров.
- Граф вызовов, исключения и `Finalizer.register` — от Spark в обоих режимах, а в `ANALYSIS` ещё и pts(`this`); сравнение со Spark содержательно по `#May Fail Cast`, `#Avg Points-to` и алиасам, а не по метрикам графа вызовов (раздел 2).
- Ветка UNEXPLAINED и ступень R5 на бенчмарках не дали ненулевого результата на исправленном эталоне; они держатся на ручных программах и чтении кода (раздел 4).
- На этом входе L_FT задаёт анализ Андерсена (`Melski2000Interconvertibility`), и на проверочных входах приёмки ответ UCFS совпадает с независимой неподвижной точкой Андерсена (раздел 3); выигрыш UCFS здесь в общности решателя (другие грамматики над тем же экспортом, E3), а не в скорости (интерпретация, E4.md «Следствие для E5»).

## 7. Воспроизведение

Полный прогон и таблицы (свежий клон, JDK 21 в `JAVA_HOME`; на машине E4-S6 прогон занял около часа):

```
git submodule update --init qilin.microben && git submodule update --init --depth 1 artifact/benchmarks && bash scripts/ucfs/bootstrap.sh
JAVA_HOME=$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2 bash ./gradlew fatJar -x test
git checkout -- artifact/Qilin-0.9.9-SNAPSHOT.jar   # fatJar копирует jar в artifact/, а e4-bench.sh пишет в meta.tsv чистоту дерева
QILIN_JAR=build/libs/Qilin-0.9.9-SNAPSHOT.jar TIMEOUT=900 XMX=16g bash scripts/ucfs/e4-bench.sh <dir> antlr bloat chart eclipse fop luindex lusearch pmd xalan checkstyle findbugs JPC
python3 acceptance/E4/tables.py <dir>
bash acceptance/E4/probe_jdk.sh
```

Проверки результатов и документа:

```
bash acceptance/E4/S6_results.sh     # результаты = код HEAD, внутренняя согласованность, повтор pmd и luindex
bash acceptance/E4/S7_doc.sh         # механика этого документа (doc_check.py)
bash acceptance/E4/S3_compare.sh     # классы = эталоны E3 на 43 программах, AndersenCheck.java, SeedCheck.java, EmptyArrayProg (R5), pmd, luindex
bash acceptance/E4/S3b_weak_type.sh  # WeakCastProg: фильтр приведения с тем же объектом типа, что у решателя
bash acceptance/E4/S4_dispatch.sh    # один шаг диспетчеризации, DispatchProg
```

Не временные значения `values.tsv` и строки `examples.tsv` воспроизводятся между прогонами на одном коде, кроме ключей pts прогонов `cov-JDK`; время не воспроизводится (раздел 6). Повтор на pmd и luindex делает `bash acceptance/E4/S6_results.sh`. Каталог прогона `e4-bench.sh` содержит, кроме сводных файлов, `sootOutput/ucfs/graph.dot`, `vertices.tsv` и `sootOutput/ucfs-compare/{metrics,pairs,dispatch}.tsv` ucfs-прогонов: по ним разобраны примеры раздела 4 и строки DISPATCH раздела 5.
