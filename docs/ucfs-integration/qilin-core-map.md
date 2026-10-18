# Карта ядра Qilin: PAG, решатель, «Ядро», запуск и точки встраивания UCFS

pin: daf57fa1ef2bb89628d251c5c74cfe25e03453a6

Часть 1 (разделы от «PAG» до «Два представления PAG») написана в стори E2-S1a, часть 2 (от «Конвейер запуска» до конца) — в E2-S1b. Каждая ссылка `путь:строка#символ` проверена на коммите из строки `pin` (исходники `qilin.*/src` и `artifact/run.py` там те же, что на `73db8b4`). Механическая проверка: `bash acceptance/E2/S1a_core_map.sh` (часть 1) и `bash acceptance/E2/S1b_core_map.sh` (вся карта). Пометка **«интерпретация»** означает вывод автора карты, который код прямо не утверждает.

Для чего карта: E3 должен выбрать граф, который получит UCFS, и знать, откуда в нём каждое ребро. Короткий ответ дан в разделе «Два представления PAG», рекомендация для E3 и E4 — в разделе «Точки встраивания UCFS».

## PAG: узлы и рёбра

PAG (pointer assignment graph, наследник Spark `Lhotak2003Scaling`) хранит рёбра в направлении потока значений: от источника к приёмнику.

### Узлы

| Ссылка | Что это |
|---|---|
| `qilin.core/src/qilin/core/pag/ValNode.java:28-49#getP2Set` | общий предок всех узлов, у которых есть множество указателей (points-to set) |
| `qilin.core/src/qilin/core/pag/LocalVarNode.java:27#LocalVarNode` | локальная переменная метода; этим же классом заданы параметры, возврат и временная переменная приведения типа |
| `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:272-289#caseRet` | узлы `this`, параметров и возврата метода имеют класс `LocalVarNode` над `Parm` и флаги межпроцедурности |
| `qilin.core/src/qilin/core/pag/GlobalVarNode.java:31#GlobalVarNode` | глобальная переменная: статическое поле (`qilin.core/src/qilin/core/builder/MethodNodeFactory.java:318-320#caseStaticFieldRef`), а также переменная строковой или классовой константы (`qilin.core/src/qilin/core/builder/MethodNodeFactory.java:328#makeGlobalVarNode`, `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:341#makeGlobalVarNode`) |
| `qilin.core/src/qilin/core/pag/AllocNode.java:33#AllocNode` | место создания объекта; это не `ValNode`, поэтому своего множества указателей у него нет |
| `qilin.core/src/qilin/core/pag/FieldRefNode.java:29-38#FieldRefNode` | обращение к полю вида база точка поле, где база есть переменная `VarNode` |
| `qilin.core/src/qilin/core/pag/FieldValNode.java:23#FieldValNode` | поле без базы, шаблон для узла поля конкретного объекта; создаётся только в решателе |
| `qilin.core/src/qilin/core/pag/ContextAllocNode.java:23-31#ContextAllocNode` | место создания объекта вместе с контекстом кучи; в глобальном графе все объекты такие |

Узел `FieldValNode` создаёт только решатель, в двух местах: `qilin.core/src/qilin/core/solver/Solver.java:260#makeFieldValNode` и `qilin.core/src/qilin/core/solver/Solver.java:273#makeFieldValNode` (проверено `grep -rn makeFieldValNode qilin.core/src qilin.pta/src`). Поэтому каждый узел `ContextField` в графе есть результат решения.

Контекстные узлы есть только в глобальном графе. Их делает `CorePTA.parameterize` из нечувствительных узлов `MethodPAG` (раздел «Ядро»):

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/pag/ContextVarNode.java:23-31#ContextVarNode` | переменная вместе с контекстом метода; в глобальном графе так представлены и локальные, и глобальные переменные |
| `qilin.core/src/qilin/core/pag/ContextField.java:30-38#ContextField` | узел поля конкретного абстрактного объекта; объект хранится первым элементом контекста, а сам узел наследует `ValNode` и имеет своё множество указателей |

Базовый объект узла `ContextField` метод `getBase` берёт из нулевого элемента контекста: `qilin.core/src/qilin/core/pag/ContextField.java:72-75#getBase`.

### Рёбра: четыре вида и правило классификации

Отдельного типа «ребро» нет. Вид ребра определяется классами его концов при добавлении:

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/pag/PAG.java:209-214#addEdge` | единственная точка добавления ребра в глобальный граф; новое ребро также кладётся парой в очередь `edgeQueue` решателя |

Правило классификации в `qilin.core/src/qilin/core/pag/PAG.java:216-229#addEdgeIntenal` такое: если оба конца `ValNode`, ребро простое (`simple`, присваивание); если источник `ValNode`, а приёмник поле, это запись (`store`); если источник `FieldRefNode`, это чтение (`load`); иначе источник `AllocNode`, и ребро есть создание объекта (`alloc`).

Следствие правила (проверено по классам): `ContextField` наследует `ValNode`, поэтому рёбра решателя `x → o.f` и `o.f → y` попадают в карту `simple`, а не в `store` или `load`. Рёбра с `FieldRefNode` приходят только из тел методов через `addToPAG`: среди выведенных ядром рёбер (таблица в разделе «Два представления PAG») нет ни одного с `FieldRefNode`.

Карты рёбер глобального графа и их публичные геттеры:

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/pag/PAG.java:134#getAlloc` | отдаёт карту рёбер создания объекта: объект указывает на множество переменных, которые получают его |
| `qilin.core/src/qilin/core/pag/PAG.java:138#getSimple` | отдаёт карту простых рёбер присваивания от источника к множеству приёмников, включая рёбра полей объектов |
| `qilin.core/src/qilin/core/pag/PAG.java:146#getLoad` | отдаёт карту рёбер чтения поля: узел обращения к полю указывает на переменные, куда читают |
| `qilin.core/src/qilin/core/pag/PAG.java:150#getStoreInv` | отдаёт обратную карту записи в поле: узел обращения к полю указывает на переменные, значения которых туда пишут |

Прямой карты записи наружу не отдаётся, геттера `getStore` нет: в блоке геттеров `qilin.core/src/qilin/core/pag/PAG.java:134-152#getSimpleInv` только эти карты и обратная простая карта. Для перебора записей нужна обратная карта или поиск `qilin.core/src/qilin/core/pag/PAG.java:260#storeLookup` по одной переменной.

### Граф метода (`MethodPAG`) и его построение

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/pag/PAG.java:528-556#getMethodPAG` | возвращает граф метода из кэша или строит его один раз, до этого применяя модели рефлексии, нативных методов и переписывание `System.arraycopy` |
| `qilin.core/src/qilin/core/pag/MethodPAG.java:190-192#getInternalReader` | читатель очереди внутренних рёбер метода: пары источник и приёмник без контекстов и без рёбер вызовов |
| `qilin.core/src/qilin/core/pag/MethodPAG.java:87-89#getInvokeStmts` | возвращает все операторы вызова метода, которые решатель потом превращает в рёбра графа вызовов |
| `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:120-127#handleStmt` | разбирает один оператор Jimple: вызов запоминается в `invokeStmts`, рёбер вызова (аргумент → параметр, возврат → результат) для него нет, а внутренние рёбра появляются только для аргумента-константы (строковой или классовой); остальные операторы дают внутренние рёбра метода |

Граф метода строится в конструкторе: `build` вызывает разбор исключений, затем обход всех операторов тела (`qilin.core/src/qilin/core/pag/MethodPAG.java:95-116#buildNormal`). Рёбра копятся парами в очереди через `qilin.core/src/qilin/core/pag/MethodPAG.java:182-188#addInternalEdge`, причём ребро с пустым источником (например, от `null`) отбрасывается.

Для вызова фабрика узлов не добавляет рёбер вызова (аргумент → параметр, возврат → результат), а создаёт узлы ссылочных аргументов, результата и получателя через `getNode`: `qilin.core/src/qilin/core/builder/MethodNodeFactory.java:133-152#handleInvokeStmt`. Внутренние рёбра при этом даёт только аргумент-константа: строковая добавляет цепочку `объект-константа → глобальная переменная → локальная переменная метода` (`qilin.core/src/qilin/core/builder/MethodNodeFactory.java:326-333#caseStringConstant`), классовая — такую же цепочку (`qilin.core/src/qilin/core/builder/MethodNodeFactory.java:339-346#caseClassConstant`). Остальные аргументы, результат и получатель — локальные переменные или поля, их ветки `getNode` рёбер не добавляют; константа `null` пропускается, другие виды констант `getNode` не разбирает (возвращает `null`). Рёбра аргументов и возврата появятся только в глобальном графе, когда решатель найдёт цель вызова.

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
- Шаг 1, простые ограничения: новая часть множества идёт по простым рёбрам, и здесь же для переменной её новые объекты исключений рассылаются по её местам броска (`qilin.core/src/qilin/core/solver/Solver.java:101-110#exceptionDispatch`).
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
| `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:169-179#addVirtualEdge` | строит контекст вызываемого метода, добавляет ребро графа вызовов и ребро от объекта получателя к переменной `this` вызываемого метода в новом контексте |
| `qilin.core/src/qilin/core/builder/CallGraphBuilder.java:227-287#processCallAssign` | для нового ребра графа вызовов добавляет рёбра от аргументов к параметрам, от возврата к результату и (при точной модели исключений) для исключений |
| `qilin.core/src/qilin/core/builder/ExceptionHandler.java:65-71#exceptionDispatch` | рассылает каждый объект исключения из множества места броска к подходящему обработчику или наружу метода |

Три параметра стратегии хранятся в полях `qilin.core/src/qilin/core/CorePTA.java:47-49#heapAbst`: конструктор контекстов, селектор контекстов и абстракция кучи. Контекст вызываемого метода строит конструктор: `qilin.core/src/qilin/core/CorePTA.java:70-72#createCalleeCtx`. Глобальная переменная всегда получает пустой контекст (`qilin.core/src/qilin/core/CorePTA.java:95-96#GlobalVarNode`), поле объекта превращается в `ContextField` (`qilin.core/src/qilin/core/CorePTA.java:102-105#makeContextField`).

Запуск ядра прост: `pureRun` вызывает `propagate` у решателя (`qilin.core/src/qilin/core/PTA.java:77-79#pureRun`), а базовый класс анализов отдаёт новый `Solver` (`qilin.pta/src/qilin/pta/tools/BasePTA.java:58-60#getPropagator`). Конструктор `PTA` создаёт граф, построитель вызовов, обработчик исключений и корневой объект `ROOT` (`qilin.core/src/qilin/core/PTA.java:61-67#rootNode`).

Spark в Qilin — это то же ядро с параметрами без контекстов: `qilin.pta/src/qilin/pta/tools/Spark.java:31-38#InsensCtxConstructor`. Селектор Spark оставляет полю объекта один элемент контекста, то есть сам объект, поэтому Spark чувствителен к полям: `qilin.core/src/qilin/parm/select/InsenSelector.java:39-42#contextTailor`.

Цепочка «быстро граф 3-4, предварительный анализ, полный граф 3-4, анализ» из AGENTS.md (интерпретация) соответствует методу `run` двухэтапных анализов (`qilin.pta/src/qilin/pta/tools/StagedPTA.java:43-48#preAnalysis`): сначала `preAnalysis`, затем сброс множеств указателей графа предварительного анализа, затем `mainAnalysis`. Например, у анализов с частичной объектной чувствительностью предварительный анализ `prePTA` — это `new Spark()`, и он запускается через `pureRun` на том же ядре: `qilin.pta/src/qilin/pta/tools/PartialObjSensPTA.java:77-89#pureRun`.

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

## Конвейер запуска: CLI → Soot → анализ → ядро → результаты

Путь одного запуска `java -jar Qilin-*.jar …` (точка входа `driver.Main.main` вызывает `mainRun`, а тот оборачивает `run` замером времени и памяти: `qilin.pta/src/driver/Main.java:59-69#mainRun`):

1. Разбор опций. `PTAOption.parseCommandLine` заполняет одиночку `PTAConfig.v()`; значение `-pta` превращается в объект шаблона (`qilin.pta/src/driver/PTAOption.java:136-138#PTAPattern`), по умолчанию это `insens`.
2. Настройка Soot: `Main.setupSoot` (опции, путь классов, загрузка классов в `PTAScene`).
3. Выбор анализа: `PTAFactory.createPTA` по шаблону (раздел «Выбор анализа по `-pta`»).
4. Запуск: `pta.run()` в `qilin.pta/src/driver/Main.java:54-56#run`. У одноэтапного анализа это `BasePTA.run`, у двухэтапного — `StagedPTA.run` (раздел «Двухэтапные анализы»).
5. Ядро: `pureRun` вызывает `getPropagator().propagate()`, то есть `Solver.propagate` из части 1.
6. Результаты и статистика: множества указателей лежат на узлах, граф вызовов отдаёт `getCallGraph`. Оценщик по умолчанию — `SimplifiedEvaluator`, с опцией `-stats` вместо него создаётся `PTAEvaluator` (`qilin.pta/src/qilin/pta/tools/BasePTA.java:36-41#PTAEvaluator`). Только он строит `PAGStat` (`qilin.core/src/qilin/stat/PTAEvaluator.java:74#PAGStat`, других `new PAGStat` в `qilin.*/src` нет, проверено `git grep -n "new PAGStat"`).

| Якорь | Роль |
|---|---|
| `qilin.pta/src/driver/Main.java:45-57#run` | главный путь CLI: разбор опций в `PTAConfig`, настройка Soot, по флагу дамп Jimple, создание анализа фабрикой по шаблону `-pta` и вызов его `run`; возвращает объект анализа |
| `qilin.pta/src/driver/Main.java:71-76#setupSoot` | настраивает Soot: опции (каталог приложения, главный класс, фазы, фантомные ссылки), путь классов из приложения, библиотек и JRE, затем загружает базовые и нужные классы в `PTAScene` |
| `qilin.pta/src/driver/PTAOption.java:113-125#parseCommandLine` | разбирает аргументы через `DefaultParser`, по `-help` печатает справку и выходит, иначе переносит значения в `PTAConfig` и строит шаблон `-pta`; любое исключение при разборе, включая неверный шаблон, даёт запись в лог и выход с кодом 1 |
| `qilin.pta/src/qilin/pta/tools/BasePTA.java:62-69#run` | полный запуск одноэтапного анализа: начало замера оценщика, `pureRun`, конец замера со сбором статистики, дампы по флагам вывода и печать отчёта оценщика |

## Объекты анализа, результаты и статистика

Иерархия: `PTA` (поля `pag`, `cgb`, `eh`, `rootNode` и запросы `reachingObjects`) ← `CorePTA` с тремя параметрами (`qilin.core/src/qilin/core/CorePTA.java:43#CorePTA`), оба в модуле `qilin.core` ← `BasePTA` в модуле `qilin.pta` (`qilin.pta/src/qilin/pta/tools/BasePTA.java:33#BasePTA`) ← `Spark`, `ObjectSensPTA`, `StagedPTA` и остальные анализы. Каждый объект анализа создаёт собственный граф `PAG` (`qilin.pta/src/qilin/pta/tools/BasePTA.java:47-50#createPAG`).

| Якорь | Роль |
|---|---|
| `qilin.core/src/qilin/core/PTA.java:77-79#pureRun` | запуск только решателя: берёт пропагатор у `getPropagator` и вызывает его `propagate`, без оценщика, статистики и дампов; так запускают предварительный Spark и тесты |
| `qilin.pta/src/qilin/pta/tools/BasePTA.java:57-60#getPropagator` | точка замены решателя: каждый вызов возвращает новый `Solver` над этим анализом; подкласс, переопределивший метод, подставляет в `pureRun` свой `Propagator` |
| `qilin.core/src/qilin/core/PTA.java:106-112#getNakedReachableMethods` | достижимые методы без контекстов: при первом вызове собирает `method()` всех пар метода и контекста из построителя графа вызовов и кэширует множество |
| `qilin.core/src/qilin/core/PTA.java:93-98#getCallGraph` | граф вызовов без контекстов: при первом вызове строится построителем из всех найденных при решении рёбер вызова, повторы цели для одного оператора и вызывающего метода убираются, результат кэшируется |
| `qilin.core/src/qilin/stat/PAGStat.java:31#PAGStat` | собственный счётчик рёбер глобального графа: суммирует размеры карт `alloc`, `simple`, `storeInv`, `load`, а внутри `simple` отдельно считает рёбра из узла поля объекта и в него |

`getCallGraph` и `getNakedReachableMethods` кэшируют результат при первом вызове, поэтому звать их нужно после решения: построитель собирает граф из `calledges` один раз (`qilin.core/src/qilin/core/builder/CallGraphBuilder.java:111-116#getCICallGraph`). Отчёт `SimplifiedEvaluator` вычитает из числа достижимых методов единицу, а из числа рёбер — вызовы точек входа из фиктивного main (`qilin.core/src/qilin/stat/SimplifiedEvaluator.java:71-73#getCallGraph`).

Результат анализа — множества указателей на узлах `ValNode.getP2Set()`. Запрос по локальной переменной объединяет множества всех её контекстных копий (`qilin.core/src/qilin/core/PTA.java:136-143#reachingObjects`), копии ищутся через `qilin.core/src/qilin/core/pag/PAG.java:481-487#getVarNodes`. Этим запросом пользуются оценщики, например при подсчёте опасных приведений типа (`qilin.core/src/qilin/stat/SimplifiedEvaluator.java:114#reachingObjects`).

Какие строки `PAGStat` печатает в выводе `-stats` (`qilin.core/src/qilin/stat/PAGStat.java:75-83#export`) и что они означают по коду подсчёта счётчиков в конструкторе (`qilin.core/src/qilin/stat/PAGStat.java:48-72#init`):
- `#Alloc-pag-edge` — сумма карты `alloc`; `#Store-pag-edge` и `#Load-pag-edge` — суммы `storeInv` и `load`, в этих двух картах только рёбра с `FieldRefNode` из тел методов;
- `#Simple-pag-edge` — сумма `simple`; из неё `#Field-to-Local` — рёбра с источником `ContextField` (`o.f → y`), `#Local-to-Field` — рёбра с приёмником `ContextField` (`x → o.f`), `#Local-to-Local` — остальное, включая рёбра аргументов и возвратов.

Поскольку `ContextField` создаёт только решатель (часть 1), сумма `#Field-to-Local` и `#Local-to-Field` есть число выведенных решателем рёбер полей объектов (у Spark — ответов Spark, R5 эпика). У двухэтапного анализа `PAGStat` считает граф основного анализа: оценщик принадлежит основному объекту, а предварительный запускается через `pureRun`.

## Двухэтапные анализы (`StagedPTA`)

| Якорь | Роль |
|---|---|
| `qilin.pta/src/qilin/pta/tools/StagedPTA.java:34#preAnalysis` | абстрактная первая стадия двухэтапного анализа: реализация запускает `prePTA` и по его результату заполняет структуры, которые затем читают селектор контекстов или абстракция кучи основного анализа |

Метод `run` двухэтапного анализа: `preAnalysis`, затем `resetPointsToSet` у графа предварительного анализа, затем `mainAnalysis` (`qilin.pta/src/qilin/pta/tools/StagedPTA.java:44-47#resetPointsToSet`). `mainAnalysis` по умолчанию вызывает `BasePTA.run` основного объекта, а с опцией `-pre` пропускается (`qilin.pta/src/qilin/pta/tools/StagedPTA.java:36-41#mainAnalysis`). Сброс (`qilin.core/src/qilin/core/pag/PAG.java:605-611#resetPointsToSet`) делает две вещи с графом предварительного анализа. Первое: сбрасывает множества указателей у всех контекстных переменных, всех узлов `ContextField` и у всех узлов из таблицы `valToValNode` (локальные и глобальные переменные, значения полей). Второе: очищает карту `addedContexts`, которую отдаёт `getMethod2ContextsMap` (какие графы методов для каких контекстов развёрнуты); после сброса эта карта у предварительного графа пуста. Остаются рёбра (карты `alloc`, `simple`, `load`, `store` и обратные), сами узлы и их контекстные карты, графы методов и построитель графа вызовов предварительного анализа: сброс их не трогает (проверено чтением кода, нет ни одной строки про них).

Во всех двухэтапных анализах на пине `prePTA` — это `new Spark()`: `qilin.pta/src/qilin/pta/tools/PartialObjSensPTA.java:77#prePTA`, `qilin.pta/src/qilin/pta/tools/PartialCallSiteSensPTA.java:77#prePTA`, `qilin.pta/src/qilin/pta/tools/ZipperPTA.java:79#prePTA`, `qilin.pta/src/qilin/pta/tools/MahjongPTA.java:50#prePTA`, `qilin.pta/src/qilin/pta/tools/BeanPTA.java:56#prePTA`; обёртка `DebloatedPTA` берёт `prePTA` у обёрнутого анализа или создаёт Spark (`qilin.pta/src/qilin/pta/tools/DebloatedPTA.java:68-72#prePTA`). Проверено `git grep -n "prePTA = "`. У анализов с частичной чувствительностью выбор передаётся основному анализу через объекты IR (переменную, выражение `new`, поле), а не через узлы графа: `qilin.core/src/qilin/util/PTAUtils.java:178-186#getIR`, его применяет `qilin.pta/src/qilin/pta/tools/PartialObjSensPTA.java:94-124#select`.

**Интерпретация фразы AGENTS.md «построили быстро граф 3-4 => предварительный анализ => построили граф 3-4 полный => анализ».** «Быстро граф 3-4» — это `prePTA.pureRun()`: Spark на том же ядре строит свой глобальный граф без контекстов. «Предварительный анализ» — остаток `preAnalysis` (у Eagle это `calculatingNode2Length`). «Полный граф 3-4» и «анализ» — это `mainAnalysis`: основной объект строит собственный граф с выборочными контекстами. В Qilin построение графа и решение — один процесс: рёбра метода попадают в глобальный граф, когда решатель делает метод достижимым (`addToPAG`, часть 1).

Замечание для тестов и шва: `StagedPTA` переопределяет только `run`, поэтому `pureRun` двухэтапного анализа запускает основной решатель без предварительной стадии. Так работает тестовый запуск `qilin.pta/test/qilin/test/util/JunitTests.java:72-82#pureRun`.

## Выбор анализа по `-pta`

| Якорь | Роль |
|---|---|
| `qilin.pta/src/driver/PTAOption.java:91-92#pointstoanalysis` | объявление опции выбора анализа: короткое имя `pta`, длинное `pointstoanalysis`, аргумент — шаблон анализа, в описании примеры `2o1h`, `2o` и значение по умолчанию `insens` |
| `qilin.pta/src/driver/PTAPattern.java:166-223#Approach` | перечень подходов (предварительных анализов и их вариантов) с длинными и короткими псевдонимами; псевдонимы образуют префикс шаблона `-pta`, шаблон без префикса получает `NONE` |
| `qilin.pta/src/driver/PTAFactory.java:45-46#createPTA` | создаёт объект анализа по паре из шаблона: сначала выбор по виду контекста, внутри по подходу; вид без своей ветки и вид `INSENS` дают `Spark` |

Разбор шаблона. Регулярное выражение `^((подход)-)?(k)(вид)(\+?(hk)h(eap)?)?$` собирается из псевдонимов подходов и видов контекста (`qilin.pta/src/driver/PTAPattern.java:38-45#getSupportPTAPattern`). Без числа `k` = 1, без кучи `hk` = `k`−1, при `k` = 0 вид становится `INSENS` (`qilin.pta/src/driver/PTAPattern.java:47-72#parsePTACommand`). Виды контекста заданы отдельным перечислением в своём файле (`insensitive/insens/ci`, `callsite/call/c`, `object/obj/o`, `hybobj/ho/h`, `hybtype/ht`, `type/t`): `qilin.pta/src/driver/ContextKind.java:27-38#ContextKind`. Затем проверяется совместимость подхода с видом (`qilin.pta/src/driver/PTAPattern.java:74-118#validateApproachCompatibility`; для `INSENS` разрешены только `SPARK` и `NONE`) и глубины (`qilin.pta/src/driver/PTAPattern.java:120-130#validateContextLength`).

Примеры по коду фабрики: `insens` — `Spark`; `2o` — `ObjectSensPTA(2, 1)`; `E-2o` — `EaglePTA(2)`, с `-cd` обёрнутый в `DebloatedPTA` (`qilin.pta/src/driver/PTAFactory.java:66-75#EaglePTA`); `T-2o` — `TurnerPTA`; `s-2c` — `SelectxPTA`. Особенность (проверено чтением кода, не запуском): у вида `HYBTYPE` в фабрике нет ветки, поэтому `-pta=2ht` проходит проверки и запускает `Spark` (`qilin.pta/src/driver/PTAFactory.java:177-179#Spark`). Класс `qilin.pta/src/qilin/pta/tools/HybridTypeSensPTA.java:34#HybridTypeSensPTA` нигде не создаётся: `git grep -n HybridTypeSensPTA daf57fa -- qilin.core qilin.pta qilin.util qilin.microben` находит только его собственный файл. Без ограничения путями `git grep` находит ещё бинарный `artifact/Qilin-0.9.9-SNAPSHOT.jar`: в нём есть запись `qilin/pta/tools/HybridTypeSensPTA.class` (проверено `unzip -l`); упоминаний класса внутри других классов jar я не искал.

Что нужно для нового подхода (например, анализа на UCFS в E3/E4; в E2 заглушку не делаем, D11):
1. константа в `Approach`, псевдоним в статическом блоке (`qilin.pta/src/driver/PTAPattern.java:184-196#approaches`) и ветка `toString`; псевдоним не должен совпадать с уже занятыми;
2. разрешение для нужного вида в `validateApproachCompatibility`;
3. ветка `case` под нужным видом в `PTAFactory.createPTA`;
4. класс анализа в `qilin.pta/src/qilin/pta/tools/` (Java, D14) поверх `BasePTA`, `StagedPTA` или `PartialObjSensPTA`;
5. имя шаблона в списке обвязки замеров `artifact/run.py:21-22#ANALYSES`: незнакомые имена `run.py` молча пропускает (`artifact/run.py:160-165#ANALYSES`), а если не распознано ни одного, подставляет `insens` без сообщения.

**Дефект `-pta=` (91d6d97, чинит E2-S2).** Коммит 91d6d97 заменил старый разборщик на `DefaultParser` (`qilin.pta/src/driver/PTAOption.java:113-115#DefaultParser`). Jar, собранный из исходников, на `-pta=insens` завершается с кодом 1 (`UnrecognizedOptionException`), а форма `-pta insens` работает; так же сломаны `-cga=`, `-cda=`, `-tc=`. Это диагноз E2.md D6, подтверждённый Oracle check; в этой стори я его не перезапускал. Обвязка замеров передаёт именно форму с равенством (`artifact/run.py:60#append`), поэтому, если диагноз D6 верен, после пересборки jar она перестанет работать до E2-S2 (следствие, не запускалось). Попутно: опция `-includeall` не действует, потому что разбор проверяет имя с опечаткой (`qilin.pta/src/driver/PTAOption.java:188#inlcudeall`).

## Точки встраивания UCFS

Четыре точки, где UCFS может войти в Qilin, с оценкой (за и против — интерпретация автора карты по коду):

| Точка | Как | За | Против |
|---|---|---|---|
| (а) офлайн после `Spark.pureRun()` | прочитать глобальный граф `qilin.core/src/qilin/core/PTA.java:81-83#getPag` и граф вызовов `getCallGraph`, перевести в рёбра UCFS, решить отдельно | ядро не меняется; Spark в том же процессе даёт эталон для сверки; счётчики `PAGStat` проверяют полноту экспорта; граф вызовов уже зафиксирован Spark | глобальный граф содержит ответы Spark (часть 1, R5 эпика), их надо отфильтровать; результат UCFS не виден метрикам Qilin без пункта (г) |
| (б) свой `Propagator` | переопределить `getPropagator` в новом подклассе `BasePTA`, как делает обёртка `qilin.pta/src/qilin/pta/tools/DebloatedPTA.java:167-170#getPropagator` | работают `pta.run()`, оценщики, дампы и выбор через `-pta` | пропагатор обязан делать всё, что делает `Solver`: подключить очереди (`qilin.core/src/qilin/core/solver/Solver.java:79-86#Solver`), сделать точки входа достижимыми, строить граф вызовов и исключения на лету и заполнять множества; UCFS ждёт готовый граф, а ядро открывает рёбра по мере роста множеств, нужен внешний цикл до неподвижной точки |
| (в) свой предварительный анализ | подкласс `PartialObjSensPTA` с `calculatingNode2Length` (`qilin.pta/src/qilin/pta/tools/PartialObjSensPTA.java:91#calculatingNode2Length`), как Eagle; для k-CFA — `PartialCallSiteSensPTA` | ровно та роль, которую в Qilin уже играет CFL-достижимость (Eagle, `He2022Qilin`); узкий контракт: карта «узел → длина контекста»; качество проверяется метриками основного анализа против `E-2o` | нужна регистрация нового подхода (`PTAPattern`, `PTAFactory`, `run.py`); UCFS решает задачу выбора контекстов, а не саму задачу указателей; время основного анализа заслоняет время UCFS |
| (г) запись результата в узлы | добавить объекты в `qilin.core/src/qilin/core/pag/ValNode.java:42-49#getP2Set` через `qilin.core/src/qilin/core/sets/DoublePointsToSet.java:113-118#add` (номер объекта кладётся в новую часть, если его нет в старой) | все метрики Qilin, построенные на `reachingObjects` (приведения, алиасы, средний размер множеств), считаются на ответе UCFS и прямо сравниваются со Spark | граф вызовов и его метрики остаются от Spark; номера объектов должны совпасть с нумератором графа; множества Spark надо сбросить или писать в свежий объект анализа; путь не проверен кодом (импорт E4) |

Как устроен предварительный анализ Eagle, на который ориентируется (в): `calculatingNode2Length` строит свой граф и возвращает карту (`qilin.pta/src/qilin/pta/tools/EaglePTA.java:47-67#calculatingNode2Length`). Граф Eagle собирается из внутренних рёбер графов методов, графа вызовов и достижимых методов предварительного Spark (`qilin.pta/src/qilin/pta/toolkits/eagle/Eagle.java:277-312#buildGraph`), а рёбра полей объектов он берёт из узлов `ContextField` (`qilin.pta/src/qilin/pta/toolkits/eagle/Eagle.java:388-398#getContextFields`), то есть тоже из ответов Spark.

**Рекомендация для E3: точка (а) на `-pta=insens`.** У Spark контексты методов и кучи пустые (контекст узла `o.f` — сам объект `o`: `InsenSelector.select` для `FieldValNode` берёт хвост контекста длины 1), и глобальный граф не размножается контекстами (R15 эпика); вход и эталон берутся из одного прогона. Какие рёбра глобального графа брать (интерпретация, решение и проверка за E3):
- брать параметризованные рёбра тел методов из всех четырёх карт, включая `store` и `load` над `FieldRefNode`: это вход;
- брать рёбра аргумент → параметр и возврат → результат: их положение задаёт граф вызовов Spark, который E3 принимает как фиксированный (расхождение R3 ниже); рёбра `ROOT → this` и `Finalizer.register` тоже вход: они зависят только от достижимости метода, а не от множеств указателей;
- не брать рёбра с `ContextField` на любом конце: это ответы Spark о полях, грамматика должна вывести их сама из `store` и `load`;
- рёбра объект получателя → `this` в карте `alloc` — тоже ответ Spark; вместо них E3 стоит построить рёбра переменная получателя → `this` цели по `getInvokeStmts` и `getCallGraph`;
- запускать без `-pe`: тогда исключения идут через статическое поле `globalThrow` внутренними рёбрами, и выведенных рёбер `ExceptionHandler` нет (расхождение R5 ниже).

Перевод узлов в вершины и рёбер в метки с обратными рёбрами описан в skill `ucfs` (`references/qilin-integration.md`); сверка результата UCFS со Spark — по `reachingObjects` с поправкой на R1–R5.

**Рекомендация для E4: точка (г)**, чтобы метрики Qilin считались на ответе UCFS, плюс регистрация шаблона `-pta` (D11) по списку выше. Точка (в) подходит этапу cfl-idr (п. 5–6 плана AGENTS.md), если его результатом будет выбор контекстов, как у Eagle (интерпретация). Точка (б) не рекомендуется: она дороже всех и спорит с графом вызовов на лету.

### Шов E2-S5

Шов — это точка (а) в коде. Это план E2-S5 (D12–D14), на пине его ещё нет, поэтому ссылок на него нет:
- Kotlin `QilinPagSeam.globalEdges(pta): Set<PagEdge>` в модуле `qilin.ucfs` читает прямые карты `alloc`, `simple`, `load`, `storeInv` глобального графа после решения и отдаёт рёбра видов `NEW`, `ASSIGN`, `LOAD`, `STORE` с исходными узлами Qilin, так что E3 может отфильтровать ответы Spark по классам узлов;
- production-вызов: опция `-ucfsseam` в `PTAOption`, в `driver.Main.run` после `pta.run()` (`qilin.pta/src/driver/Main.java:54-56#run`) Java-класс из `qilin.pta/src` вызывает `globalEdges` и печатает 4 строки `#UCFS-seam-<KIND>: <n>`;
- оракул: счётчики равны строкам `PAGStat` того же прогона с `-stats` (`NEW` = `#Alloc-pag-edge`, `ASSIGN` = `#Simple-pag-edge`, `LOAD` = `#Load-pag-edge`, `STORE` = `#Store-pag-edge`), плюс обратные карты в `E2PagSeamTest`.

После `pta.run()` двухэтапного анализа (`E-2o`) `getPag` отдаёт граф основного анализа, а не предварительного Spark. Исключение, найденное чтением кода: с `-cd` фабрика возвращает обёртку `DebloatedPTA`, которая не переопределяет `getPag`, и её собственный граф решатель не заполняет (решает `basePTA`); шву тогда нужен граф `basePTA` (вывод по коду, не запуском). E3 расширяет именно этот Java-класс (D14).

## Расхождения UCFS и Spark (R1–R5 из NOVELTY S0)

Это список из `docs/ai/library/NOVELTY.md`, а не риски эпика E2 с теми же номерами. Ответ UCFS совпадёт со Spark лишь с поправкой на эти расхождения (полнота списка не проверена, он взят из NOVELTY):
- **R1, фильтрация по типам.** Каждое добавление объекта в множество указателей при решении (обе версии `Solver.propagatePTS`) проверяет тип (`qilin.core/src/qilin/util/PTAUtils.java:349-354#addWithTypeFiltering`); в базовой постановке CFL-достижимости (грамматика над метками рёбер) такой проверки нет (интерпретация). Пары UCFS можно отфильтровать после решения тем же `castNeverFails`, но фильтр в конце отсекает меньше, чем фильтр на каждом шаге, поэтому ответ UCFS будет надмножеством ответа Spark (интерпретация, проверит E3).
- **R2, приведения типа.** Приведение даёт временную переменную с типом приведения (`qilin.core/src/qilin/core/builder/MethodNodeFactory.java:265-270#caseCastExpr`), и сужение типа на ней работает только через R1.
- **R3, граф вызовов на лету.** Цели вызовов выбираются по множеству получателя во время решения (`qilin.core/src/qilin/core/builder/CallGraphBuilder.java:214-220#virtualCallDispatch`); для UCFS граф вызовов Spark зафиксирован заранее.
- **R4, модели библиотек и JVM.** Фиктивный main с точками входа (с `-se` берутся только точки входа приложения, без неявных; при `-clinit FULL` к ним в любом случае добавляются `<clinit>`; `qilin.core/src/qilin/core/builder/FakeMainFactory.java:55-78#getEntryPoints`), модели рефлексии, нативных методов и `System.arraycopy` при построении графа метода (`qilin.core/src/qilin/core/pag/PAG.java:528-556#getMethodPAG`). Они уже лежат в рёбрах методов, поэтому экспорт их сохраняет, если берёт все достижимые методы вместе с фиктивным main.
- **R5, массивы, статические поля, исключения.** Все элементы массива — одно поле (`qilin.core/src/qilin/core/builder/MethodNodeFactory.java:297-299#caseArray`), а тип узла `o.f` без `-pae` всегда `java.lang.Object`, с `-pae` это объявленный тип поля (для элемента массива — тип элемента массива базы) (`qilin.core/src/qilin/core/pag/ContextField.java:40-43#preciseArrayElement`). Статические поля всегда с пустым контекстом (`qilin.core/src/qilin/core/CorePTA.java:95-96#GlobalVarNode`). Без `-pe` бросок пишет в общее поле `globalThrow` (`qilin.core/src/qilin/core/builder/MethodNodeFactory.java:204-208#caseThrowStmt`), а места бросков для решателя не строятся (`qilin.core/src/qilin/core/pag/MethodPAG.java:118-121#buildException`). Запрет записи и чтения у пустых массивов (`qilin.core/src/qilin/core/solver/Solver.java:342-346#disallowStoreOrLoadOn`) аналога в грамматике не имеет. Флаги `-pae`, `-pe`, `-sc`, `-mh` должны быть одинаковы у Spark и у экспорта.

## Модуль `qilin.ucfs`

Сейчас в сборке три модуля (`settings.gradle:1-4#include`), `qilin.pta` зависит от `qilin.core` (`qilin.pta/build.gradle:45-47#project`), а UCFS подключён только к тестам `qilin.pta` после E1 (`qilin.pta/build.gradle:52-53#testImplementation`). Модуль `qilin.ucfs` (Kotlin, KGP 2.4.0, E2-S3) встаёт между ними.

**Направление зависимостей: `qilin.ucfs` → `qilin.core`, `qilin.pta` → `qilin.ucfs` (D2).** Обоснование:
- всё, что нужно шву, лежит в `qilin.core`: `PTA` (`qilin.core/src/qilin/core/PTA.java:53#PTA`), `CorePTA`, `PAG`, `MethodPAG`, узлы, а настройки читаются через `qilin.core/src/qilin/CoreConfig.java:28-33#CoreConfig`. `qilin.core` не импортирует `qilin.pta` (проверено: `git grep -c "import qilin.pta" daf57fa -- qilin.core/src` пуст; в `qilin.core` есть лишь строки с именами классов `qilin.pta.nativemodel.*` в `NativeMethodDriver` и упоминания в комментариях);
- CLI и выбор анализа (`driver.Main`, `PTAOption`, `PTAPattern`, `PTAFactory`) лежат в `qilin.pta`. Чтобы `-ucfsseam` (E2-S5), а в E3/E4 новый шаблон `-pta` вызывали модуль, `qilin.pta` должен видеть `qilin.ucfs`. Обратная зависимость дала бы цикл;
- `qilin.core` подключает Soot как `implementation` (`qilin.core/build.gradle:14-17#implementation`), поэтому Kotlin-коду с типами Soot нужен свой Soot (D9);
- классы, которым нужны `BasePTA`, `Spark` или `PTAConfig` из `qilin.pta`, пишутся на Java в `qilin.pta/src` и вызывают Kotlin API модуля. Первый такой production-класс — вызов шва в E2-S5 (D14), его расширит E3.

Модуль попадает в CLI-jar через `fatJar`, который собирает `runtimeClasspath` корня (`build.gradle:39-47#fatJar`); его зависимость от jar подпроектов чинит E2-S4 (D7).
