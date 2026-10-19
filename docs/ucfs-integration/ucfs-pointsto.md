# UCFS как решатель points-to над PAG Qilin

pin: 0d64de50915ccd510374ce9a37b5a36a7a6ad3e8
ucfs-pin: bd1c1110674ce8c22c4281d766318563c8322341

Документ стори E3-S5 (эпик E3, п. 3 плана: «экспорт в граф и UCFS, проверка — почему алгоритм работает на разных грамматиках»). Ссылка `путь:строка#символ` указывает на код Qilin-AI-exp на коммите из строки `pin`, ссылка `ucfs:путь:строка#символ` — на код UCFS в клоне `.ucfs/src` на коммите из строки `ucfs-pin` (это `ucfsCommit` из `gradle.properties`). Механика документа проверяется командой `bash acceptance/E3/S5_ucfs_doc.sh`.

Пометка «интерпретация» означает вывод автора, который код или тест прямо не утверждает. Пометка «проверено:» называет код или команду, которые утверждение подтверждают. Числа разделов 4 и 5 получены командами, названными рядом с ними, на коммите этого документа. Абсолютные числа пар зависят от состава тестовой JVM (E3.md, RS7), поэтому сверять их имеет смысл на одном коммите и в одном прогоне.

Коротко:
- вход UCFS — глобальный PAG законченного прогона Spark (`-pta=insens`) без рёбер узлов `o.f`; часть оставшихся рёбер `new` построил решатель Spark по своим points-to, это посчитано (раздел 5);
- грамматика — L_FT из `Sridharan2005Demand` (Fig. 3, p. 6), по паре терминалов на поле;
- один и тот же GLL UCFS работает на разных грамматиках, потому что грамматика превращается в данные (RSM), а цикл разбора эти данные читает и от вида грамматики не меняется (раздел 3); исполняемая проверка — 10 грамматик на случайных графах и две грамматики на 43 программах (раздел 4);
- на 43 малых программах ответ UCFS содержит ответ Spark (missing=0), лишние 47 пар разобраны по классам R4b, R1, R2 (раздел 5).

## 1. Экспорт PAG в граф UCFS

После `pta.run()` экспорт читает четыре карты глобального PAG Qilin (`alloc`, `simple`, `load`, `storeInv`) через шов E2: `qilin.ucfs/src/main/kotlin/qilin/ucfs/QilinPagSeam.kt:68-85#globalEdges`. Рёбра идут по направлению потока значений, узлы не копируются.

Затем экспорт отбрасывает рёбра с концом в узле поля объекта `ContextField` и переводит остальные рёбра в метки UCFS: `qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:133-154#ContextField`. Вершины графа — плотные номера CI-узлов: контекстный узел заменяется своим `base()` (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:192-197#ci`); для `insens` эта проекция ничего не склеивает, это интерпретация решения D3 эпика; тест S1 проверяет, что вершины — CI-узлы без повторов (`qilin.pta/test/qilin/test/ucfs/E3PagExportTest.java:124-130#isCiVertex`). Вместе с каждым ребром `u -l-> v` добавляется обратное `v -l_bar-> u`, потому что вторая половина alias читает flowsTo в обратную сторону (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:123-128#bar`; `Sridharan2005Demand`, p. 4–5). Строки меток — контракт E3.md D4 (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PtLabels.kt:15-35#PtLabels`).

| Ребро PAG Qilin | Оператор Jimple | Ребро графа UCFS |
|---|---|---|
| `AllocNode o → VarNode v` | `v = new T` | `o -new-> v` |
| `u → v` (карта `simple`) | `v = u`, аргумент → параметр, возврат → результат | `u -assign-> v` |
| `y → x.f` (карта `storeInv`) | `x.f = y` | `y -store_i-> x` (от значения к базе) |
| `x.f → z` (карта `load`) | `z = x.f` | `x -load_i-> z` (от базы к результату) |

Номер `i` — плотный номер поля `SparkField`. Ориентация store и load совпадает с putfield и getfield у `Sridharan2005Demand` (p. 4). Элементы массивов в PAG Qilin — одно поле `ArrayElement`, статическое поле — вершина `GlobalVarNode` с рёбрами `assign`.

### Какая часть входа — ответ Spark (B1)

Глобальный PAG — не исходная программа, а состояние решателя после его неподвижной точки. Три места qilin.core, где решатель добавляет рёбра по своим points-to, и объект экспорта:

| Якорь | Роль в экспорте |
|---|---|
| `qilin.core/src/qilin/core/solver/Solver.java:254-265#handleStoreEdge` | для оператора `x.f = y` решатель добавляет ребро `y → o.f` от записываемого значения `y` к узлу поля `o.f` каждого объекта `o`, уже найденного в points-to базы `x` (симметрично `handleLoadEdge` для `z = x.f` добавляет `o.f → z`); экспорт рёбра с узлами `o.f` отбрасывает, иначе UCFS получил бы полевую часть ответа готовой |
| `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:169-179#addVirtualEdge` | при диспетчеризации вызова решатель кладёт ребро «объект получателя → this вызванного метода»; основной режим экспорта оставляет его, второй режим заменяет рёбрами assign |
| `qilin.core/src/qilin/core/builder/ExceptionHandler.java:76-104#dispatch` | решатель кладёт ребро «выброшенный объект → переменная catch или узел выброса метода»; в обоих режимах экспорта оно остаётся во входе как есть |
| `qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:16-72#PagExport` | объект экспорта; его KDoc перечисляет отброшенные и оставленные рёбра, `export(pta)` вызывает основной режим |

Ещё два вида рёбер `new` не взяты из операторов программы. Ребро «объект → параметр `Finalizer.register`» решатель добавляет для объектов с финализатором (`qilin.core/src/qilin/core/solver/Solver.java:227-241#handleImplicitCallToFinalizerRegister`); на 43 программах таких рёбер 0 (раздел 5). Ребро «ROOT → this у fakeMain» связывает точку входа и не читается из points-to (`qilin.core/src/qilin/core/builder/CallGraphBuilder.java:134-139#getEntryPoints`), поэтому тест S3 считает его отдельным классом, а не выведенным ребром. Рёбра «аргумент → параметр» и «возврат → результат» Qilin строит по рёбрам графа вызовов Spark (`qilin.core/src/qilin/core/builder/CallGraphBuilder.java:227-271#processCallAssign`), они попадают в граф как `assign`.

### Основной режим: связывание this из Spark (D2)

`PagExport.export(pta)` — режим `ReceiverBinding.ANALYSIS`: рёбра «объект получателя → this» экспортируются как есть, так что pts(this) и потоки исключений приходят от Spark, а UCFS решает копирование и полевую часть поверх них. Так устроен пайплайн AGENTS.md «Kernel+Solver[low-cost] => UCFS»: дешёвый Spark идёт первым, UCFS работает по его результату. Прецедент такого связывания — пре-анализ Eagle в Qilin: он берёт points-to `this` у предварительного Spark (`qilin.pta/src/qilin/pta/toolkits/eagle/Eagle.java:333-338#reachingObjects`; реализация Eagle над Spark в Soot — `Lu2021Eagle`, p. 34). `Sridharan2005Demand` прецедентом основного режима не является: там граф вызовов строит CHA, а вызов моделируется рёбрами assign (p. 9), это прецедент второго режима.

CLI-опция `-ucfspt` (стори S4) использует основной режим: `qilin.pta/src/qilin/pta/ucfs/UcfsPointsToDump.java:64-67#export` вызывает `PagExport.export(pta)` и затем `UcfsPointsTo.solve` с `PointsToGrammar` на число полей графа.

### Второй режим: `ReceiverBinding.CALL_GRAPH` (D15)

`PagExport.export(pta, ReceiverBinding.CALL_GRAPH)` пропускает рёбра `new` в CI-узел `this`, кроме ребра от ROOT (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:138-143#bindByCallGraph`). Вместо них после карт PAG добавляются рёбра «переменная-получатель → this вызванного метода» (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:155-159#receiverAssigns`). Пары берутся из рёбер CI-графа вызовов Spark, выходящих из экземплярных мест вызова, которые решатель записал в карту получателей (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:168-188#receiverToSitesMap`). В этом режиме pts(this) считает UCFS. Фильтра диспетчеризации нет: `this` вызванного метода получает points-to переменной-получателя целиком, поэтому ответ может вырасти (класс R3; описание режима — `qilin.ucfs/src/main/kotlin/qilin/ucfs/ReceiverBinding.kt:21-37#CALL_GRAPH`). Прецедент — `Sridharan2005Demand` (p. 9): граф вызовов зафиксирован заранее, параметры и возвраты вызова — рёбра assign.

В обоих режимах из Spark остаются граф вызовов (какие методы вызывает место вызова, рёбра аргументов и возвратов), рёбра исключений и ребро в параметр `Finalizer.register`. Поэтому метрики графа вызовов у ответа UCFS совпадут со Spark по построению, если E4 не пересчитает диспетчеризацию (интерпретация, вывод E3.md «Следствие для E4»).

## 2. Грамматика points-to

Андерсен для Java выражается как CFL-достижимость (`Melski2000Interconvertibility`; грамматика L_FT — `Sridharan2005Demand`, Fig. 3, p. 6). В Fig. 3 скобки — putfield[f] и getfield[f] с их обратными версиями. В UCFS грамматика пишется в DSL Kotlin, а затем строится в RSM (`Alur2005Analysis`; GLL над RSM — `Abzalov2026Gll`, p. 3).

```
flowsTo    -> new step*                    flowsTo   Fig. 3: new (assign | putfield[f] alias getfield[f])*
step       -> assign | store_i alias load_i       (по альтернативе на поле i)
flowsToBar -> stepBar* new_bar             flowsTo~  Fig. 3: (assign~ | getfield[f]~ alias putfield[f]~)* new~
stepBar    -> assign_bar | load_i_bar alias store_i_bar
alias      -> flowsToBar flowsTo
```

| Якорь | Роль |
|---|---|
| `qilin.ucfs/src/main/kotlin/qilin/ucfs/grammar/PointsToGrammar.kt:48-77#PointsToGrammar` | грамматика L_FT над полями от 0 до k−1: пять нетерминалов, стартовый `flowsTo`, терминалы строятся через `PtLabels` |
| `qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsPointsTo.kt:29-43#UcfsPointsTo` | запрос points-to: экспорт основного режима, `PointsToGrammar` на число полей графа и решатель UCFS от вершин-объектов |

Как закодированы поля (D5). Терминал DSL UCFS — одно сравниваемое значение `Term(value)`, а правило нельзя параметризовать полем (`ucfs:solver/src/main/kotlin/org/ucfs/rsm/symbol/Term.kt:6#Term`), поэтому у поля `i` свои терминалы `store_i`, `load_i` и их версии `_bar`, а правило `step` повторяет альтернативу `store_i alias load_i` по разу на поле. Один и тот же номер `i` по обе стороны `alias` и разделяет поля: alias рекурсивно содержит store и load всех полей, поэтому язык не разлагается на отдельную грамматику на поле (интерпретация решения D5). Альтернативы объединены сбалансированным деревом `or` глубины около log2(k) (`qilin.ucfs/src/main/kotlin/qilin/ucfs/grammar/PointsToGrammar.kt:84-90#balancedOr`): левая свёртка на тысячах альтернатив переполняет стек при сборке RSM (E3.md D5; верификатор E3-S2 получил переполнение от 5000 альтернатив, это его проба, здесь не повторялась). Нетерминалы `step` и `stepBar` только именуют группы под звёздой Fig. 3, язык `flowsTo` от этого не меняется (интерпретация; совпадение с эталоном по Fig. 3 — раздел 4).

Запрос (D6). Слово flowsTo начинается с `new`, а ребро `new` выходит из объекта, поэтому решатель запускается от вершин-объектов, и ответ — пары (объект, переменная): `qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsPointsTo.kt:60-72#reachablePairs`. Стартовые вершины задаются через `addStartVertex`, а не фильтром ответа по всем парам (`qilin.ucfs/src/main/kotlin/qilin/ucfs/UcfsSolver.kt:76-94#addStartVertex`). В карту ответа идут пары, у которых первая вершина — `AllocNode`, а вторая — `VarNode`.

Второе прочтение Fig. 3 — грамматика points-to команды UCFS: рёбра там идут от переменной к объекту, а метка `_r` обозначает обратное ребро (`ucfs:cfpq-paths-app/src/main/kotlin/org/ucfs/paths/Main.kt:18-35#PointsTo`). Её нетерминал `PointsTo`, обобщённый в тесте с 4 полей на k полей, на графе с переименованными метками даёт обратные пары `PointsToGrammar` (раздел 4, `ucfsTeamGrammarGivesReversedPairs`). Это закрывает прочтение п. 3 AGENTS.md «разные грамматики points-to»; основное прочтение — «разные грамматики вообще» (интерпретация, E3.md «Допущения»).

## 3. Почему GLL работает на разных грамматиках

Тезис: грамматика компилируется в данные — RSM, набор конечных автоматов (боксов) по одному на нетерминал с рёбрами по терминалам и нетерминалам (`Alur2005Analysis`). GLL UCFS — один интерпретатор этих данных над графом, как в `Abzalov2026Gll` (p. 3), где GLL работает над RSM вместо BNF. Ниже шесть доводов (а)–(е) по коду UCFS на `ucfs-pin`; общей формальной корректности документ не доказывает, это интерпретация кода, подкреплённая исполняемой проверкой раздела 4.

### (а) Грамматика превращается в данные RSM

| Якорь | Роль |
|---|---|
| `ucfs:solver/src/main/kotlin/org/ucfs/grammar/combinator/Grammar.kt:36-45#buildRsm` | строит бокс RSM для каждого нетерминала грамматики и ещё фиктивный стартовый бокс `fictiveStart` над стартовым нетерминалом; возвращает его стартовое состояние |
| `ucfs:solver/src/main/kotlin/org/ucfs/rsm/RsmState.kt:49-89#buildRsmBox` | строит бокс по регулярному выражению правой части: состояние на каждую новую производную, ребро по символу, если производная не пустая |
| `ucfs:solver/src/main/kotlin/org/ucfs/grammar/combinator/regexp/Regexp.kt:4-22#derive` | производная Бжозовского регулярного выражения по символу; финальность состояния задаёт `acceptEpsilon` этого выражения |

Нетерминал DSL хранит свою правую часть как регулярное выражение и при сборке создаёт стартовое состояние бокса (`ucfs:solver/src/main/kotlin/org/ucfs/grammar/combinator/regexp/Nt.kt:28-31#buildRsmBox`). Производная конкатенации следует формуле `D[s](h.t)` с учётом пустого слова в голове (`ucfs:solver/src/main/kotlin/org/ucfs/grammar/combinator/regexp/Concatenation.kt:8-26#derive`). Буквами алфавита при этом служат и терминалы, и нетерминалы, поэтому ребро бокса по нетерминалу попадает в отдельный список `nonterminalEdgesStorage`, а по терминалу — в `terminalEdgesStorage` (`ucfs:solver/src/main/kotlin/org/ucfs/rsm/RsmState.kt:16-43#terminalEdgesStorage`). Новое состояние финально, если его выражение принимает пустое слово (`ucfs:solver/src/main/kotlin/org/ucfs/rsm/RsmState.kt:45-47#getNewState`). RSM строится один раз на экземпляр грамматики (`ucfs:solver/src/main/kotlin/org/ucfs/grammar/combinator/Grammar.kt:18-25#rsm`).

Парсер получает от грамматики только стартовое состояние фиктивного бокса и его финальное состояние (`ucfs:solver/src/main/kotlin/org/ucfs/parser/Gll.kt:29-34#gll`). Дальше разбор использует у состояния RSM флаг `isFinal`, списки `terminalEdgesStorage` и `nonterminalEdgesStorage`, `startState` нетерминала на ребре, а сами состояния — как ключи узлов GSS и диапазонов SPPF. Пакеты разбора не ссылаются на DSL грамматик, проверено: `git -C .ucfs/src grep -c -E 'grammar[.]combinator|Regexp|Grammar' bd1c111 -- solver/src/main/kotlin/org/ucfs/parser solver/src/main/kotlin/org/ucfs/intersection solver/src/main/kotlin/org/ucfs/gss solver/src/main/kotlin/org/ucfs/descriptors solver/src/main/kotlin/org/ucfs/sppf` (пустой вывод). Значит, грамматика влияет на разбор только через рёбра и флаги состояний RSM (интерпретация этого поиска и чтения кода).

### (б) Цикл parse / handleDescriptor / handleEdges не зависит от грамматики

| Якорь | Роль |
|---|---|
| `ucfs:solver/src/main/kotlin/org/ucfs/parser/IGll.kt:24-40#parse` | главный цикл: создаёт стартовые дескрипторы и обрабатывает дескрипторы, пока рабочий стек дескрипторов не пуст; возвращает корни разбора |
| `ucfs:solver/src/main/kotlin/org/ucfs/parser/IGll.kt:48-61#initDescriptors` | для каждой стартовой вершины графа создаёт узел GSS и дескриптор в стартовом состоянии фиктивного бокса |
| `ucfs:solver/src/main/kotlin/org/ucfs/parser/Gll.kt:76-86#handleDescriptor` | помечает дескриптор обработанным, в финальном состоянии бокса делает возврат, затем передаёт дескриптор движку пересечения |
| `ucfs:solver/src/main/kotlin/org/ucfs/intersection/IntersectionEngine.kt:12-40#handleEdges` | для исходящих рёбер текущей вершины графа ищет ребро RSM с тем же терминалом, затем проходит рёбра RSM по нетерминалам |
| `ucfs:solver/src/main/kotlin/org/ucfs/parser/IGll.kt:96-116#handleTerminalEdge` | совпавшее ребро графа: терминальный узел SPPF, промежуточный узел и дескриптор в конце ребра в следующем состоянии RSM |
| `ucfs:solver/src/main/kotlin/org/ucfs/parser/IGll.kt:63-93#handleNonterminalEdge` | вызов нетерминала: ребро GSS к узлу вызываемого бокса, дескриптор в его старте и продолжение по уже найденным возвратам |

Дескриптор — четвёрка (вершина графа, узел GSS, состояние RSM, узел SPPF), как `(L, u, i, w)` у `Scott2013Gll` (p. 12–13), где позиция строки заменена вершиной графа (`Grigorev2017Context`, p. 3–4). В этих функциях нет ветвления по виду грамматики: они перебирают рёбра состояния RSM и рёбра вершины графа одинаково для любой RSM, а конкретная грамматика меняет только набор рёбер и финальность состояний (интерпретация чтения кода выше).

### (в) Общий узел GSS и прошлые возвраты: левая рекурсия и циклы графа

| Якорь | Роль |
|---|---|
| `ucfs:solver/src/main/kotlin/org/ucfs/gss/GraphStructuredStack.kt:15-32#addEdge` | при вызове берёт общий узел GSS для пары (вершина, стартовое состояние вызываемого бокса), добавляет ребро к вызывающему и возвращает возвраты, уже сделанные из этого узла |
| `ucfs:solver/src/main/kotlin/org/ucfs/gss/GraphStructuredStack.kt:35-44#pop` | при возврате запоминает найденный диапазон в узле GSS и отдаёт рёбра к вызывающим, известным на этот момент |
| `ucfs:solver/src/main/kotlin/org/ucfs/parser/Gll.kt:88-110#handleTerminalRsmState` | в финальном состоянии бокса делает возврат для вызывающих по рёбрам GSS и записывает корень разбора, если диапазон отвечает на запрос |

Узел GSS — data-класс с полями (состояние RSM, вершина), его равенство определяют только эти поля (`ucfs:solver/src/main/kotlin/org/ucfs/gss/GssNode.kt:14-36#GssNode`), а `getOrCreateNode` возвращает уже созданный равный узел (`ucfs:solver/src/main/kotlin/org/ucfs/gss/GraphStructuredStack.kt:10-13#getOrCreateNode`). Это узел `(A, i)` из `Afroozeh2015Faster` (p. 7–9): стартовое состояние бокса однозначно задаёт нетерминал A, а вершина играет роль позиции i (соответствие — интерпретация). Возврат продолжает вызывающего через `handlePoppedGssEdge` (`ucfs:solver/src/main/kotlin/org/ucfs/parser/Gll.kt:49-68#handlePoppedGssEdge`).

Связь двух сторон — как множество P у `Scott2010Gll` (p. 7): вызывающий, пришедший к узлу позже возврата, получает прошлые возвраты из `popped` (в `handleNonterminalEdge`), а возврат, случившийся позже вызова, проходит по всем рёбрам GSS, известным к этому моменту (в `pop`). Поэтому результат вызова нетерминала в вершине считается один раз и раздаётся вызывающим (интерпретация; проверено: `ucfs:solver/src/main/kotlin/org/ucfs/parser/IGll.kt:76-91#positionToPops`).

Левая рекурсия, например `S -> S S | a`: дескриптор в стартовом состоянии `S` в вершине v вызывает `S` в той же вершине, `getOrCreateNode` отдаёт тот же узел GSS, и новый стартовый дескриптор равен уже обработанному, поэтому отбрасывается (довод (г)); результат вызова дойдёт через петлю GSS, когда `S` что-то разберёт (интерпретация). Цикл графа работает так же: повтор вершины даёт уже известные пары (вершина, состояние), новых узлов GSS не появляется. Узлов GSS не больше, чем вершин, умноженных на состояния RSM (интерпретация из равенства data-класса).

### (г) Повторный дескриптор отбрасывается: довод о завершении

| Якорь | Роль |
|---|---|
| `ucfs:solver/src/main/kotlin/org/ucfs/descriptors/DescriptorsStorage.kt:20-28#add` | кладёт дескриптор в рабочий стек (`addLast`, а `nextToHandle` берёт `removeLast`), если равный ему ещё не обрабатывался; `handleDescriptor` помечает дескриптор обработанным первым делом |

Дескриптор — data-класс из четырёх полей (`ucfs:solver/src/main/kotlin/org/ucfs/descriptors/Descriptor.kt:11-31#Descriptor`), узел SPPF — data-класс из диапазона вершин, диапазона состояний RSM и типа, дети в равенство не входят (`ucfs:solver/src/main/kotlin/org/ucfs/sppf/node/RangeSppfNode.kt:21-27#RangeSppfNode`). При конечном графе и конечной RSM различных узлов GSS, узлов SPPF и, значит, дескрипторов конечное число (интерпретация). Дескриптор, равный обработанному, `add` не принимает, поэтому цикл `parse` заканчивается на любом конечном графе, в том числе с циклами и при леворекурсивной грамматике (интерпретация; это довод, а не доказательство). Оговорка по коду: `add` сверяет дескриптор с множеством обработанных, но не с рабочим стеком, поэтому копия, добавленная до первой обработки, будет обработана ещё раз. Это лишняя работа, а не бесконечная: копий до первой обработки конечное число (интерпретация). Дескриптор у `Scott2010Gll` проверяется по множеству U (p. 7) — та же роль.

### (д) SPPF переиспользует узлы: неоднозначность

| Якорь | Роль |
|---|---|
| `ucfs:solver/src/main/kotlin/org/ucfs/sppf/SppfStorage.kt:21-32#addNonterminalNode` | узел нетерминала для диапазона после возврата; если такой диапазон уже есть, возвращается прежний узел Range, а новый ребёнок добавляется к его узлу нетерминала |
| `ucfs:solver/src/main/kotlin/org/ucfs/sppf/SppfStorage.kt:53-69#addIntermediateNode` | промежуточный узел, склеивающий разобранную часть с новым куском; пустая левая часть не создаёт нового узла |

Оба метода сводятся к закрытому `addNode`, который ищет узел в хеш-таблице и добавляет ребёнка, только если его там ещё нет (`ucfs:solver/src/main/kotlin/org/ucfs/sppf/SppfStorage.kt:71-89#addNode`). Разные выводы одного диапазона попадают под один узел Range: разные точки склейки дают разных детей этого узла, а равные узлы повторно не создаются (типы узлов и переиспользование Range — `Abzalov2026Gll`, p. 3; бинаризованный SPPF — `Scott2013Gll`, p. 7). Поэтому на неоднозначной грамматике, например `S -> S S | a | ε`, число выводов может быть бесконечным, а число узлов SPPF и дескрипторов остаётся конечным (интерпретация, связка с доводом (г)).

### (е) ε-диапазоны дают пары (v, v)

| Якорь | Роль |
|---|---|
| `ucfs:solver/src/main/kotlin/org/ucfs/parser/Gll.kt:70-74#isParseResult` | корень разбора засчитывается, если диапазон начинается в стартовой вершине и проходит фиктивный бокс от старта до финала |

Если дескриптор стоит в финальном состоянии, а разобранного ещё нет (`EmptyType`), `handleTerminalRsmState` строит ε-узел с диапазоном вершин `(v, v)` (`ucfs:solver/src/main/kotlin/org/ucfs/parser/Gll.kt:37-47#getEpsilonRange`). Сам ε-узел `isParseResult` не проходит: его диапазон RSM — `(S_start, S_start)` в боксе стартового нетерминала `S`, а не от старта до финала фиктивного бокса; ε-узла в старте фиктивного бокса тоже не бывает, потому что этот старт не финален (правая часть фиктивного бокса — один нетерминал, `DerivedSymbol`, у него `acceptEpsilon` ложно: `ucfs:solver/src/main/kotlin/org/ucfs/grammar/combinator/regexp/Regexp.kt:13-21#acceptEpsilon`). Когда `S` выводит пустое слово, возврат из бокса `S` к узлу GSS фиктивного бокса строит над ε-узлом узел нетерминала с диапазоном вершин `(v, v)` и диапазоном RSM от старта до финала фиктивного бокса (`ucfs:solver/src/main/kotlin/org/ucfs/parser/Gll.kt:49-63#handlePoppedGssEdge`; пустая левая часть возвращает его без промежуточного узла). Когда обрабатывается дескриптор в финале фиктивного бокса с этим узлом, узел проходит `isParseResult`, и в ответе появляется пара `(v, v)` для стартовой вершины v; для вершин вне стартов она не появляется (проверено: `bash acceptance/E3/S2_points_to_grammar.sh`, случай `explicitStartVertices`). ε-узлы `(v, ε, v)` описаны и у `Grigorev2017Context` (p. 5). У `flowsTo` пустого слова нет (оно начинается с `new`), а `UcfsPointsTo` отбрасывает пары, вторая вершина которых не переменная, поэтому в points-to пар `(o, o)` нет.

## 4. Проверка: один решатель и один экспорт на разных грамматиках

Эталон грамматик — рабочий список CFL-достижимости над грамматикой, нормализованной вручную до правил `A -> ε | t | B | B C` (`qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E3GrammarTest.kt:63-91#reference`; схема — `Melski2000Interconvertibility`, алгоритм с нормализацией — `Reps1998Program`, p. 5). Он не использует UCFS и его DSL. Эталон points-to на программах — Андерсен по картам PAG в Java-тесте (REF без фильтров, REF_T с фильтрами Qilin).

| Проверка | Что сравнивается | Результат (прогон этого коммита) |
|---|---|---|
| `E3GrammarTest.otherGrammarsAgainstReference` | 9 грамматик × 120 случайных графов, UCFS против эталона | равны; графов с парой u ≠ v: a^n b^n 62, Dyck-2 с ε 71, `S -> S S \| a` 104, `new assign*` 95, скрытая левая рекурсия 96, цикл единичных правил 108, `S -> S S \| a \| ε` 95, вложенные звёзды 98, правая рекурсия 95 |
| `E3GrammarTest.pointsToRandomGraphsWithBars` и `pointsToRandomGraphsAnyLabels` | `PointsToGrammar(k)` против эталона Fig. 3, по 150 графов, k от 1 до 3 | равны на 300 графах |
| `E3GrammarTest.ucfsTeamGrammarGivesReversedPairs` | грамматика команды UCFS на переименованных метках против `PointsToGrammar` | обратные пары равны на 150 графах, непустых 100 |
| `E3GrammarTest.manyFields` | `PointsToGrammar(2000)`, поля не смешиваются | ответ равен ожидаемому; время сборки RSM и запроса печатает строка `E3GrammarTest manyFields`, оно порядка секунд, меняется от прогона к прогону и не контракт |
| `E3UcfsPointsToTest.allProgramsAgainstReferences` | один экспорт, две грамматики на 43 программах: L_FT против REF, `new assign*` против BFS по рёбрам new/assign | равны на 43 программах |
| `E3ReceiverAssignTest.callGraphBindingAllPrograms` | второй режим: граф = построенному тестом, UCFS = REF2 | равны на 43 программах |

Числа таблицы — проверено: `bash acceptance/E3/S2_points_to_grammar.sh` (строки `E3GrammarTest …`), `bash acceptance/E3/S3_ucfs_pointsto.sh` и `bash acceptance/E3/S3b_receiver_assign.sh`. Порог «у каждой грамматики не меньше 30 графов с парой u ≠ v» тест проверяет сам, пары `(v, v)` в счёт не идут (проверено: `qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E3GrammarTest.kt:302-314#nonTrivial`). Экспорт проверяет `E3PagExportTest` (S1): граф совпадает с графом по картам PAG, факты пяти программ (`bash acceptance/E3/S1_pag_export.sh`, входит в `bash acceptance/E3/E3_e2e.sh`).

Какие доводы раздела 3 нагружает каждая грамматика (интерпретация по виду грамматик): левая рекурсия — `S -> S S | a` и скрытая левая рекурсия `S -> A S b | c` с `A -> ε | a`, довод (в); циклы графа — случайные графы с повторами вершин, доводы (в) и (г); неоднозначность — `S -> S S | a` и `S -> S S | a | ε`, довод (д); пустое слово — Dyck-2 и `S -> S S | a | ε`, довод (е); цикл единичных правил `S -> T | a`, `T -> S | b` — `S` вызывает себя через `T` в той же вершине, доводы (в) и (г); нерегулярные языки и вложенная рекурсия — a^n b^n, Dyck-2 и сама L_FT; регулярные — `new assign*` и вложенные звёзды.

L_FT не леворекурсивна ни прямо, ни скрыто: правые части `step` и `stepBar` начинаются с терминала, `flowsTo` — с `new`, `flowsToBar` — со `stepBar` или `new_bar`, а `alias` — с `flowsToBar`, поэтому пустого префикса перед рекурсивным вызовом нет (проверено: `qilin.ucfs/src/main/kotlin/qilin/ucfs/grammar/PointsToGrammar.kt:67-76#alias`). Рекурсия `alias` внутри `step` и `stepBar` вложенная: между вызовами читается хотя бы одно ребро `store_i` или `load_i_bar`. Повторный вызов `alias` в той же вершине у L_FT возможен только через цикл графа, и тогда работает тот же общий узел GSS довода (в); в непустом экспортированном графе циклы есть всегда, потому что у каждого ребра есть обратное `_bar` (`qilin.ucfs/src/main/kotlin/qilin/ucfs/PagExport.kt:123-128#bar`; что L_FT нагружает этим довод (в) — интерпретация).

## 5. Расхождения со Spark

Числа — проверено: `bash acceptance/E3/S3_ucfs_pointsto.sh`, строка `E3UcfsPointsToTest total: programs=43 ucfsPairs=4338 sparkPairs=4291 missing=0 extra=47 extraR4b=43 extraR1=3 extraR2=1 extraR5=0 newEdges=1479 derivedNew=919 derivedNewIntoThis=651 pairsWithoutDerivedNew=1931`: на 43 программах UCFS не теряет ни одной пары Spark (missing=0), а лишних пар 47 = 43 (extraR4b) + 3 (extraR1) + 1 (extraR2). Класс каждой лишней пары назначает тест: он включает фильтры решателя по одному (ROOT, объявленный тип, тип приведения, пустые массивы), и пара получает класс шага, на котором исчезла (`qilin.pta/test/qilin/test/ucfs/E3UcfsPointsToTest.java:578-597#perClass`). Сумма классов обязана равняться числу лишних пар, иначе тест падает (`qilin.pta/test/qilin/test/ucfs/E3UcfsPointsToTest.java:649-651#perClass`, решение D16). Поэтому «UCFS воспроизводит Spark» верно только по модулю классов R1–R5 и R4b (интерпретация в смысле NOVELTY.md).

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/util/PTAUtils.java:349-354#addWithTypeFiltering` | фильтр Spark по типу: объект попадает в points-to переменной, только если его тип совместим с объявленным типом узла; у UCFS такого фильтра нет |
| `qilin.core/src/qilin/core/sets/HybridPointsToSet.java:167-196#add` | малое множество Spark хранит номера в массиве, где 0 означает пустую ячейку, поэтому объект с номером 0 в нём не виден |

| Класс | Что | Наблюдение (43 программы) |
|---|---|---|
| R1 | фильтр по объявленному типу переменной и поля, в том числе тип элемента массива | extraR1=3; три строки `extra` с `class=R1` относятся к `array.ArrayElemTypeFiltering`: `a` и `Parm 0` у `Assert.notAlias`, `i` в `main` с объектом `H`; у трёх строк `removedAloneBy=[R1, R2]`, то есть пару убирает поодиночке и R1, и R2 |
| R2 | тип узла приведения | extraR2=1: сам узел приведения `(G) h`, который Soot вставил перед записью в массив, с объектом `H` |
| R3 | граф вызовов на лету | 0 в основном режиме по построению (D2); во втором режиме growthR3=8 |
| R4 | модели библиотек и JVM | входят в PAG с обеих сторон, отдельных пар 0 |
| R4b | ROOT невидим в points-to Spark | extraR4b=43: пара (ROOT, this у fakeMain), одна на программу |
| R5 | пустые массивы, массивы одним полем, статика, исключения | extraR5=0 |

Механика R1 и R2 одна: решатель добавляет объект в множество через `addWithTypeFiltering` с типом узла (`qilin.core/src/qilin/core/solver/Solver.java:319-339#propagatePTS`), а у временной переменной приведения тип — тип приведения. R5 у решателя — запрет store и load на пустом массиве (`qilin.core/src/qilin/core/solver/Solver.java:341-346#disallowStoreOrLoadOn`). R4b: контекстный узел ROOT создаётся конструктором `PTA` напрямую, без нумератора, и получает номер 0 (`qilin.core/src/qilin/core/PTA.java:61-67#rootNode`); `forall` малого множества останавливается на первой ячейке с 0 (`qilin.core/src/qilin/core/sets/HybridPointsToSet.java:132-146#forall`). Тест проверяет, что объект с номером 0 в каждой программе ровно один и это ROOT (проверено: `qilin.pta/test/qilin/test/ucfs/E3UcfsPointsToTest.java:664-666#zero`). Для множества, уже переведённого в битовый вектор, номер 0 был бы виден; что ROOT туда не попадает, следует из равенства REF_T = Spark на 43 программах, а не из кода (интерпретация).

Доля входа, которую сделал Spark (B1, D1). Из newEdges=1479 рёбер `new` во входе UCFS не из оператора программы и не от ROOT построил решатель Spark derivedNew=919 (62.1 %): по своим points-to — derivedNewIntoThis=651 рёбер «получатель → this» и derivedNewException=268 рёбер исключений; рёбер в `Finalizer.register` 0 (проверено: `bash acceptance/E3/S3_ucfs_pointsto.sh`, сумма полей `derivedNewException` и `derivedNewFinalizer` по 43 строкам программ; `bash acceptance/E3/S3b_receiver_assign.sh` печатает тот же итог derivedNewException=268). Рёбра в `Finalizer.register` решатель добавляет не по points-to, а когда включает в PAG достижимый метод, в котором выделяется объект с финализатором (`qilin.core/src/qilin/core/solver/Solver.java:203-222#addToPAG`). Без выведенных рёбер UCFS находит pairsWithoutDerivedNew=1931 пар из 4338, то есть 44.5 % ответа; остальные 55.5 % пар зависят от рёбер, которые построил Spark (доля — интерпретация чисел одного прогона, RS7). Ответ без выведенных рёбер тест сверяет с Андерсеном на том же урезанном входе.

Второй режим (`ReceiverBinding.CALL_GRAPH`, проверено: `bash acceptance/E3/S3b_receiver_assign.sh`, строка `E3ReceiverAssignTest total: programs=43 ucfsPairs1=4260 ucfsPairs2=4268 growthR3=8 sparkPairs=4213 missing=0 receiverAssign=709 derivedNewIntoThis=0 derivedNewException=268`). Рёбер «объект → this» во входе не осталось (derivedNewIntoThis=0), добавлено 709 рёбер assign «получатель → this», Spark по-прежнему входит в ответ UCFS (missing=0), и ответ основного режима тоже (тест проверяет это отдельно). Прирост growthR3=8 пар весь в `assign.Receiver2This` (49 → 57 пар), у 42 других программ прирост 0 (проверено: `bash acceptance/E3/S3b_receiver_assign.sh | grep 'growthR3=[1-9]'` даёт строку этой программы и строку total). Причина — связывание без фильтра диспетчеризации: в `test(a, b)` переменная `a` указывает на объекты A и B, вызов `a.foo(b)` по графу Spark идёт в `A.foo` и `B.foo`, и `this` у `A.foo` получает оба объекта; утверждение `notAlias(this, o)` в `A.foo` для UCFS становится «may alias» (проверено: `qilin.pta/test/qilin/test/ucfs/E3ReceiverAssignTest.java:178-198#receiver2ThisCallGraphBinding`).

Абсолютные числа зависят от состава JVM: в прогоне S3b основной режим дал 4260 пар UCFS и 4213 Spark, в прогоне S3 — 4338 и 4291 на тех же 43 программах; разность 47 совпала (E3.md RS7, причина не выяснена). Ответы внутри одного прогона тесты сравнивают между собой, а не с числами из документа.

## 6. Ограничения

- **Масштаб не доказан.** Проба `acceptance/E3/probe_scale.sh` (неблокирующая, M5) запускает `-ucfspt` на `assign.CastFail`: глобальный PAG 291 199 рёбер (new 105 969, assign 178 021, load 4 208, store 3 001), прогон с `-ucfspt` не закончился за 540 с при `-Xmx16g` (`finished=no exit=124 wall_s=541`), пик RSS 7838 МиБ у реализатора S4 и 9561 МиБ у верификатора S4. Источник — разделы Implementer и Verifier тикета E3-S4; в этой стори пробу я не повторял. Это одно наблюдение на прогон, не замер; 16 программ qilin.microben, которые доходят до JDK, в проверках UCFS не участвуют.
- **Стоимость RSM растёт с числом полей.** На 2000 полях сборка RSM занимает порядка секунд (строка `E3GrammarTest manyFields` в выводе S2, время от прогона меняется); у JDK-программ 1356 полей, у DaCapo может быть больше (E3.md RS1). Поиск ребра RSM по терминалу в `handleEdges` линейный по числу терминальных рёбер состояния (`ucfs:solver/src/main/kotlin/org/ucfs/intersection/IntersectionEngine.kt:23-27#terminalEdgesStorage`), а у состояний `step` их порядка числа полей, так что и он растёт с полями (интерпретация, не замерялось).
- **Нет фильтра типов в грамматике.** Ответ UCFS — надмножество Spark на 43 программах (R1, R2, R4b); на других программах это ожидание, не проверка. В алгоритме `Sridharan2005Demand` типы учитываются (p. 6–7), в нашей L_FT — нет; метрики точности без пост-фильтра не могут быть лучше Spark по построению, а при лишних парах — хуже (интерпретация, E3.md RS4).
- **Граф вызовов, исключения и Finalizer — из Spark в обоих режимах**; в основном режиме ещё и pts(this). Сравнение с Spark в E4 имеет смысл по avg points-to, may-fail casts и алиасам, а не по метрикам графа вызовов (интерпретация, E3.md «Следствие для E4»).
- **Проверены шаблон `insens` и CI-проекция.** Другие шаблоны `-pta` дают проекцию своего графа, она не проверялась (RS3). Второй режим в CLI не выведен.
- **Полевая чувствительность на 43 программах не различима**: полевая нечувствительная замена `store_i alias load_i` ответ на них не меняет (мутация M3d раунда 1), её ловит синтетика S2 (`manyFields`, случайные графы; E3.md D14).
- **ROOT (R4b)** даёт одну лишнюю пару на программу; учитывать ли её в метриках, решает E4 (D13).
- **Доводы раздела 3 — объяснение по коду, а не доказательство корректности и не оценка сложности.** Оценки из статей (`Grigorev2017Context`, `Afroozeh2015Faster`, `Scott2013Gll`) сделаны для их версий GLL; переносить их на UCFS без анализа кода и замера нельзя (интерпретация, NOVELTY.md). Выводы `Abzalov2026Gll` о скорости получены на RDF-графах и к Java PTA не относятся.
- **Структурные проверки обходимы намеренно** (RS9): байткод S3 и журнал классов S4 ловят реализацию без UCFS, но не «вызвать UCFS и вернуть свой ответ с тем же значением»; это закрывается чтением кода (`UcfsPointsTo.solve(pta)` возвращает результат `solve(graph, grammar)` без обработки).
