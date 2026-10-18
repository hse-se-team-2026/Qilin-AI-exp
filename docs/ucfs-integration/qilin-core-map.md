# Карта ядра Qilin, часть 1: PAG, решатель, «Ядро»

pin: daf57fa1ef2bb89628d251c5c74cfe25e03453a6

Стори E2-S1a. Каждая ссылка `путь:строка#символ` проверена на коммите из строки `pin` (исходники `qilin.*/src` там те же, что на `73db8b4`). Механическая проверка: `bash acceptance/E2/S1a_core_map.sh`. Пометка **«интерпретация»** означает вывод автора карты, который код прямо не утверждает. Вторую часть (CLI, `-pta`, точки встраивания, шов, модуль `qilin.ucfs`) пишет E2-S1b.

Для чего карта: E3 должен выбрать граф, который получит UCFS, и знать, откуда в нём каждое ребро. Короткий ответ дан в разделе «Два представления PAG».

## PAG: узлы и рёбра

PAG (pointer assignment graph, наследник Spark `Lhotak2003Scaling`) хранит рёбра в направлении потока значений: от источника к приёмнику.

### Узлы

| Ссылка | Что это |
|---|---|
| `qilin.core/src/qilin/core/pag/ValNode.java:28-49#getP2Set` | общий предок всех узлов, у которых есть множество указателей (points-to set) |
| `qilin.core/src/qilin/core/pag/LocalVarNode.java:27#LocalVarNode` | локальная переменная метода; этим же классом заданы параметры, возврат и временная переменная приведения типа |
| `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:272-289#caseRet` | узлы `this`, параметров и возврата метода имеют класс `LocalVarNode` над `Parm` и флаги межпроцедурности |
| `qilin.core/src/qilin/core/pag/GlobalVarNode.java:31#GlobalVarNode` | глобальная переменная: статическое поле, а также переменная строковой или классовой константы |
| `qilin.core/src/qilin/core/pag/AllocNode.java:33#AllocNode` | место создания объекта; это не `ValNode`, поэтому своего множества указателей у него нет |
| `qilin.core/src/qilin/core/pag/FieldRefNode.java:29-38#FieldRefNode` | обращение к полю вида база точка поле, где база есть переменная `VarNode` |
| `qilin.core/src/qilin/core/pag/FieldValNode.java:23#FieldValNode` | поле без базы, шаблон для узла поля конкретного объекта; создаётся только в решателе |
| `qilin.core/src/qilin/core/pag/ContextAllocNode.java:23-31#ContextAllocNode` | место создания объекта вместе с контекстом кучи; в глобальном графе все объекты такие |

Узел `FieldValNode` создаёт только решатель, в двух местах: `qilin.core/src/qilin/core/solver/Solver.java:260#makeFieldValNode` и `qilin.core/src/qilin/core/solver/Solver.java:273#makeFieldValNode` (проверено `grep -rn makeFieldValNode qilin.core/src qilin.pta/src`). Поэтому каждый узел `ContextField` в графе есть результат решения.

Контекстные узлы есть только в глобальном графе. Их делает `CorePTA.parameterize` из нечувствительных узлов `MethodPAG` (раздел «Ядро»):

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/pag/ContextVarNode.java:23-31#ContextVarNode` | переменная вместе с контекстом метода; в глобальном графе так представлены и локальные, и глобальные переменные |
| `qilin.core/src/qilin/core/pag/ContextField.java:30-38#ContextField` | узел поля конкретного абстрактного объекта; объект хранится первым элементом контекста, а наследует узел класс `ValNode` |

Базовый объект узла `ContextField` метод `getBase` берёт из нулевого элемента контекста: `qilin.core/src/qilin/core/pag/ContextField.java:72-75#getBase`.

### Рёбра: четыре вида и правило классификации

Отдельного типа «ребро» нет. Вид ребра определяется классами концов в одном методе:

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/pag/PAG.java:209-214#addEdge` | единственная точка добавления ребра в глобальный граф; новое ребро также кладётся парой в очередь `edgeQueue` решателя |

Правило классификации в `qilin.core/src/qilin/core/pag/PAG.java:216-229#addEdgeIntenal` такое: если оба конца `ValNode`, ребро простое (`simple`, присваивание); если источник `ValNode`, а приёмник поле, это запись (`store`); если источник `FieldRefNode`, это чтение (`load`); иначе источник `AllocNode`, и ребро есть создание объекта (`alloc`).

Следствие правила (проверено по классам): `ContextField` наследует `ValNode`, поэтому рёбра решателя `x → o.f` и `o.f → y` попадают в карту `simple`, а не в `store` или `load`. В картах `store` и `load` остаются только рёбра с `FieldRefNode`, то есть рёбра из тел методов.

Карты рёбер глобального графа и их публичные геттеры:

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/pag/PAG.java:134#getAlloc` | отдаёт карту рёбер создания объекта: объект указывает на множество переменных, которые получают его |
| `qilin.core/src/qilin/core/pag/PAG.java:138#getSimple` | отдаёт карту простых рёбер присваивания от источника к множеству приёмников, включая рёбра полей объектов |
| `qilin.core/src/qilin/core/pag/PAG.java:146#getLoad` | отдаёт карту рёбер чтения поля: узел обращения к полю указывает на переменные, куда читают |
| `qilin.core/src/qilin/core/pag/PAG.java:150#getStoreInv` | отдаёт обратную карту записи в поле: узел поля указывает на переменные, значения которых туда пишут |

Прямой карты записи наружу не отдаётся, геттера `getStore` нет: в блоке геттеров `qilin.core/src/qilin/core/pag/PAG.java:134-152#getSimpleInv` только эти карты и обратная простая карта. Для перебора записей нужна обратная карта или поиск `qilin.core/src/qilin/core/pag/PAG.java:260#storeLookup` по одной переменной.

### Граф метода (`MethodPAG`) и его построение

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/pag/PAG.java:528-556#getMethodPAG` | возвращает граф метода из кэша или строит его один раз, до этого применяя модели рефлексии и нативных методов |
| `qilin.core/src/qilin/core/pag/MethodPAG.java:190-192#getInternalReader` | читатель очереди внутренних рёбер метода: пары источник и приёмник без контекстов и без рёбер вызовов |
| `qilin.core/src/qilin/core/pag/MethodPAG.java:87-89#getInvokeStmts` | возвращает все операторы вызова метода, которые решатель потом превращает в рёбра графа вызовов |
| `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:120-127#handleStmt` | разбирает один оператор Jimple: вызов только запоминается, остальные операторы дают внутренние рёбра метода |

Граф метода строится в конструкторе: `build` вызывает разбор исключений, затем обход всех операторов тела (`qilin.core/src/qilin/core/pag/MethodPAG.java:95-116#buildNormal`). Рёбра копятся парами в очереди через `qilin.core/src/qilin/core/pag/MethodPAG.java:182-188#addInternalEdge`, причём ребро с пустым источником (например, от `null`) отбрасывается.

Для вызова фабрика узлов рёбер не добавляет, только создаёт узлы аргументов, результата и получателя: `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:133-152#handleInvokeStmt`. Рёбра аргументов и возврата появятся только в глобальном графе, когда решатель найдёт цель вызова.

Внутренние рёбра дают присваивание, возврат, идентичность (параметры, `this`, пойманное исключение) и, при неточной модели исключений, бросок в `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:161-210#handleIntraStmt`. Приведение типа добавляет ребро к новой типизированной временной переменной: `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:265-270#caseCastExpr`. Строковая константа даёт цепочку из объекта константы через глобальную переменную в локальную: `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:326-333#caseStringConstant`.

## Решатель (слой 4, `Solver`)

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/solver/Propagator.java:31#propagate` | абстрактный метод распространения множеств указателей по графу; единственная обязанность любого решателя |
| `qilin.core/src/qilin/core/solver/Solver.java:89-124#propagate` | главный цикл со списком работ и дельтами: инициализация, затем четыре шага для каждой извлечённой вершины (шаги 2 и 3 только для переменных) |
| `qilin.core/src/qilin/core/solver/Solver.java:126-147#processStmts` | для каждого нового достижимого метода с контекстом добавляет его рёбра и регистрирует его вызовы и броски |
| `qilin.core/src/qilin/core/solver/Solver.java:203-225#addToPAG` | переносит внутренние рёбра метода в глобальный граф: абстракция кучи, параметризация контекстом, вызов общего добавления ребра |
| `qilin.core/src/qilin/core/solver/Solver.java:243-252#handleStoreAndLoadOnBase` | шаг два: для новых объектов базы обрабатывает все записи в её поля и все чтения из них |
| `qilin.core/src/qilin/core/solver/Solver.java:254-265#handleStoreEdge` | для каждого объекта базы, кроме пустых массивов, создаёт узел поля объекта и добавляет ребро от записываемой переменной к нему |
| `qilin.core/src/qilin/core/solver/Solver.java:267-278#handleLoadEdge` | для каждого объекта базы, кроме пустых массивов, создаёт узел поля объекта и добавляет ребро от него к читающей переменной |
| `qilin.core/src/qilin/core/solver/Solver.java:280-317#activateConstraints` | шаг четыре: обрабатывает новые места вызовов, новые броски и все новые рёбра графа по старым множествам |
| `qilin.core/src/qilin/core/solver/Solver.java:319-333#propagatePTS` | добавляет объекты с фильтрацией по типу и ставит вершину в список работ, если её множество выросло |
| `qilin.core/src/qilin/util/PTAUtils.java:349-354#addWithTypeFiltering` | фильтрация по типам: объект добавляется, только если его тип можно присвоить объявленному типу указателя |

Список работ — упорядоченное множество `ValNode` (`qilin.core/src/qilin/core/solver/Solver.java:68#valNodeWorkList`). Множество указателей двойное: шаг работает с новой частью (`getNewSet`), а после шага 3 она сливается со старой (`qilin.core/src/qilin/core/solver/Solver.java:120#flushNew`).

Порядок работы `propagate`:
- Инициализация: вызывается построитель графа вызовов (точки входа), затем `processStmts` для них, затем все рёбра создания объекта засевают множества (`qilin.core/src/qilin/core/solver/Solver.java:94-96#initReachableMethods`).
- Шаг 1, простые ограничения: новая часть множества идёт по простым рёбрам, и здесь же объекты исключений рассылаются по местам броска (`qilin.core/src/qilin/core/solver/Solver.java:101-110#exceptionDispatch`).
- Шаг 2, запись и чтение по базе: для полей переменной вызывается `handleStoreAndLoadOnBase`, она порождает рёбра `x → o.f` и `o.f → y` (`qilin.core/src/qilin/core/solver/Solver.java:112#handleStoreAndLoadOnBase`).
- Шаг 3, виртуальные вызовы: новые объекты получателя рассылаются по его местам вызова, затем разбираются новые достижимые методы (`qilin.core/src/qilin/core/solver/Solver.java:114-118#virtualCallDispatch`).
- Шаг 4, активация: `activateConstraints` дочитывает очереди новых вызовов, бросков и рёбер (`qilin.core/src/qilin/core/solver/Solver.java:122#activateConstraints`).

В шаге 4 по каждому новому ребру применяется старое множество его источника: копирование для пары переменных или узла поля объекта, чтение и запись через базу, засев для создания объекта (`qilin.core/src/qilin/core/solver/Solver.java:300-316#addedEdges`). Так ребро, добавленное в середине решения, догоняет уже посчитанные множества.

Метод `addToPAG` обрабатывает каждую пару метода и контекста один раз (`qilin.core/src/qilin/core/solver/Solver.java:204-207#getMethod2ContextsMap`) и читает рёбра через копию читателя (`qilin.core/src/qilin/core/solver/Solver.java:208#getInternalReader`). Рёбра от объекта к глобальной переменной он кладёт с пустым контекстом через `qilin.core/src/qilin/core/pag/PAG.java:200-204#addGlobalPAGEdge`. Вывод для экспорта (интерпретация): внешний код тоже должен читать через `clone()`, иначе он сдвинет общий читатель, и последующие контексты метода потеряют рёбра.

Узел поля объекта строится в два шага: сначала из объекта получается контекст, где первым элементом стоит сам объект, а за ним его контекст кучи (`qilin.core/src/qilin/util/PTAUtils.java:615-632#plusplusOp`), затем `parameterize` делает из `FieldValNode` узел `ContextField`. Записи и чтения у пустых массивов запрещены: `qilin.core/src/qilin/core/solver/Solver.java:342-346#disallowStoreOrLoadOn`.

Совместимость типов проверяет `qilin.core/src/qilin/util/PTAUtils.java:308-326#castNeverFails`: тип `null` проходит всегда, иначе решает иерархия классов Soot.

## Ядро (слои 3–4 `docs/QilinArchitecture.png`)

**Интерпретация.** В AGENTS.md сказано «алгоритм Solver. Стратегия "Ядро". (3-4)». На рисунке `docs/QilinArchitecture.png` (Fig. 2 из `He2022Qilin`) слой 3 называется «Parameterized Pointer Analysis Kernel» (тонкая контекстная чувствительность, граф вызовов на лету, исключения на лету), слой 4 — «Incremental Worklist-based Solver». Карта считает «Ядром» оба слоя: `CorePTA` с параметрами, `CallGraphBuilder`, `ExceptionHandler`, `Solver` и `PAG` с `MethodPAG`. Слой 5 (обработчики сложных возможностей Java) входит в ядро через `getMethodPAG`: рефлексия и нативные методы моделируются при построении графа метода.

**Альтернатива «Ядро = только `Solver`» отклонена.** Код показывает, что слой 4 без слоя 3 не работает: цикл решателя сам вызывает рассылку виртуальных вызовов (`qilin.core/src/qilin/core/solver/Solver.java:116#virtualCallDispatch`) и рассылку исключений, а контексты узлов ему даёт `parameterize` из `CorePTA`. Без слоя 3 нет ни графа вызовов, ни контекстов, а значит, нет и межпроцедурных рёбер.

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/CorePTA.java:79-100#parameterize` | переводит нечувствительный узел в контекстный по его виду: переменная, обращение к полю, объект, поле объекта, глобальная |
| `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:141-147#initReachableMethods` | помещает точки входа в множество достижимых методов и в очередь, которую затем читает решатель |
| `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:214-220#virtualCallDispatch` | для каждого объекта из множества получателя выбирает цели виртуального вызова по типу этого объекта |
| `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:169-179#addVirtualEdge` | строит контекст вызываемого метода, добавляет ребро графа вызовов и ребро от объекта получателя к его переменной этого |
| `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:227-287#processCallAssign` | для нового ребра графа вызовов добавляет рёбра от аргументов к параметрам, от возврата к результату и для исключений |
| `qilin.core/src/qilin/core/builder/ExceptionHandler.java:65-71#exceptionDispatch` | рассылает каждый объект исключения из множества места броска к подходящему обработчику или наружу метода |

Три параметра стратегии хранятся в полях `qilin.core/src/qilin/core/CorePTA.java:47-49#heapAbst`: конструктор контекстов, селектор контекстов и абстракция кучи. Контекст вызываемого метода строит конструктор: `qilin.core/src/qilin/core/CorePTA.java:70-72#createCalleeCtx`. Глобальная переменная всегда получает пустой контекст (`qilin.core/src/qilin/core/CorePTA.java:95-96#GlobalVarNode`), поле объекта превращается в `ContextField` (`qilin.core/src/qilin/core/CorePTA.java:102-105#makeContextField`).

Запуск ядра прост: `pureRun` вызывает `propagate` у решателя (`qilin.core/src/qilin/core/PTA.java:77-79#pureRun`), а базовый класс анализов отдаёт новый `Solver` (`qilin.pta/src/qilin/pta/tools/BasePTA.java:58-60#getPropagator`). Конструктор `PTA` создаёт граф, построитель вызовов, обработчик исключений и корневой объект `ROOT` (`qilin.core/src/qilin/core/PTA.java:61-67#rootNode`).

Spark в Qilin — это то же ядро с параметрами без контекстов: `qilin.pta/src/qilin/pta/tools/Spark.java:31-38#InsensCtxConstructor`. Селектор Spark оставляет полю объекта один элемент контекста, то есть сам объект, поэтому Spark чувствителен к полям: `qilin.core/src/qilin/parm/select/InsenSelector.java:39-42#contextTailor`.

Цепочка «быстро граф 3-4, предварительный анализ, полный граф 3-4, анализ» из AGENTS.md (интерпретация) соответствует методу `qilin.pta/src/qilin/pta/tools/StagedPTA.java:43-48#preAnalysis`: предварительный анализ, сброс множеств указателей, основной анализ. Например, у анализов с частичной объектной чувствительностью предварительный анализ `prePTA` — это `new Spark()`, и он запускается через `pureRun` на том же ядре: `qilin.pta/src/qilin/pta/tools/PartialObjSensPTA.java:77-89#pureRun`.

Другие точки, где граф вызовов меняет глобальный граф: статический вызов (`qilin.core/src/qilin/core/builder/CallGraphBuilder.java:191-197#addStaticEdge`) и общая обработка нового ребра, которая делает цель достижимой и вызывает `processCallAssign` (`qilin.core/src/qilin/core/builder/CallGraphBuilder.java:199-207#handleCallEdge`).

## Два представления PAG

**1. Внутренние рёбра `MethodPAG`.** Это рёбра одного метода без контекстов и без рёбер вызовов, доступные через `getInternalReader`. Это вход решателя для метода: `addToPAG` параметризует их контекстом. Сами по себе они межпроцедурного потока не описывают.

**2. Глобальный граф `PAG` после `pureRun()`.** Карты `getAlloc`, `getSimple`, `getLoad`, `getStoreInv` содержат контекстные узлы (`ContextVarNode`, `ContextAllocNode`, `ContextField`) и два класса рёбер.

Первый класс — рёбра методов, параметризованные контекстом, после абстракции кучи (`qilin.core/src/qilin/core/solver/Solver.java:211-222#heapAbstractor`). Только в этом классе есть рёбра `store` и `load` над `FieldRefNode`.

Второй класс — рёбра, выведенные ядром при решении. Их источники в коде (полный список вызовов `addEdge` глобального графа, проверено `grep -rn "\.addEdge(" qilin.core/src qilin.pta/src`; остальные совпадения относятся к собственным графам инструментов `qilin.pta`):

| Ребро | Где добавляется | В какую карту |
|---|---|---|
| `ROOT` → `this` фиктивного main | `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:134-139#getEntryPoints`, добавление ребра в строке 137 точки входа | в карту создания, источник объект |
| объект получателя → `this` цели | `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:175#addEdge` внутри метода добавления виртуального ребра | в карту создания, источник объект |
| аргумент → параметр | `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:252#addEdge` для каждого ссылочного аргумента найденного вызова | в простую карту рёбер присваивания |
| возврат → переменная результата | `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:267#addEdge` если результат вызова присваивается ссылочной переменной | в простую карту рёбер присваивания |
| бросок цели → переменная исключения вызова | `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:285#addEdge` только при точной модели исключений | в простую карту рёбер присваивания |
| `x → o.f` (запись в поле объекта) | `qilin.core/src/qilin/core/solver/Solver.java:262#addEdge` для каждого объекта из множества базы | в простую карту, приёмник поле объекта |
| `o.f → y` (чтение поля объекта) | `qilin.core/src/qilin/core/solver/Solver.java:275#addEdge` для каждого объекта из множества базы | в простую карту, источник поле объекта |
| объект исключения → переменная обработчика | `qilin.core/src/qilin/core/builder/ExceptionHandler.java:92#addEdge` если тип подходит ловушке; иначе ребро к узлу броска метода в строке 101 | в карту создания, источник объект |
| объект → параметр `Finalizer.register` | `qilin.core/src/qilin/core/solver/Solver.java:229-241#handleImplicitCallToFinalizerRegister` для объектов классов с финализатором | в карту создания, источник объект |

**Часть этих рёбер — уже результаты Spark (R5 в E2.md).** Рёбра `объект → this`, все узлы `ContextField` с рёбрами `x → o.f` и `o.f → y`, а также рёбра аргументов и возвратов виртуальных вызовов существуют только потому, что решатель уже нашёл соответствующие множества указателей. Если отдать UCFS глобальный граф целиком, UCFS частично перепроверит Spark, а не решит задачу сам. Отличить такие рёбра можно по классам узлов (интерпретация, проверит E3): `ContextField` на любом конце; ребро создания, приёмник которого — переменная `this` (у тел методов таких рёбер нет); простое ребро в параметр или из возврата. Рёбра вызовов можно оставить как вход, решение за E3.

Для каких контекстов был развёрнут каждый граф метода, показывает карта `qilin.core/src/qilin/core/pag/PAG.java:446-448#getMethod2ContextsMap`, а все узлы полей объектов отдаёт `qilin.core/src/qilin/core/pag/PAG.java:450-452#getContextFields`.

## Выбор анализа `-pta` (E2-S1b)

Заглушка, раздел пишет E2-S1b.

## Точки встраивания и шов (E2-S1b)

Заглушка, раздел пишет E2-S1b.

## Модуль `qilin.ucfs` (E2-S1b)

Заглушка, раздел пишет E2-S1b.
