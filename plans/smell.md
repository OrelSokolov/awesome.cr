# Plan: группа `smell` — design-smell guard'ы

Status: каркас реализован (команда `awesome smell`, базовый
`Guard#test_project`, `Awesome::Index`, спеки `spec/index_spec.cr` /
`spec/project_pass_spec.cr`). Guard'ы группы — не реализованы.

Группа `smell` — третий вид проверок после `speed` и `memory`: не
производительность, а design-smell'и — механически проверяемые признаки
плохой структуры кода. Происхождение группы — вопрос «можно ли проверять
SOLID»: честный ответ — целиком нет. Из пяти букв механически видны полторы:

- **D** (Dependency Inversion) → `HardcodedDependency`
- **S** (Single Responsibility) — только прокси-метрики → `GodClass`
- **L** (Liskov) — пара узких случаев, пока не реализуем
- **O** (Open/Closed) — видно только в истории коммитов, не в снапшоте кода
- **I** (Interface Segregation) — требует семантики вызовов

Поэтому группа называется `smell`, а не `solid`: каждый guard детектирует
конкретный факт (порог, анти-паттерн), а не «нарушение принципа» — и не
обещает того, что в AST не видно. Общие правила группы — как у всех guard'ов
awesome: лучше false negative, чем false positive.

Архитектура: guard'ы делятся на per-file (`test(source, config)`, как все
существующие) и per-project (`test_project(sources, config)` + синтаксический
`Index` иерархии). Per-project часть — детально в
[project_guards.md](project_guards.md); здесь — каталог guard'ов группы.

## Wiring группы

- `CLI::COMMANDS` + banner + kind-фильтр: `awesome smell [paths]`
  (`src/awesome/cli.cr`).
- `README.md`: строка в usage, группа в таблице guard'ов.
- Каждый guard: `src/awesome/guards/<name>.cr` (KIND = `"smell"`, константы
  `SHORT_DESCRIPTION` / `GOOD_EXAMPLE` / `BAD_EXAMPLE`), спека в `spec/`,
  док `docs/guards/<name>.md`, пример в `examples/awful/<name>.cr`
  (один файл на guard — конвенция AGENTS.md).

## Guard'ы

### 1. `HardcodedDependency` — per-file

Smell: DIP. Класс сам создаёт свои зависимости (`SomeConcrete.new` в теле
метода) вместо инъекции через конструктор — жёсткая сцепленность, нельзя
подменить в тесте.

- Check: внутри `ClassDef` — `Call` с именем `new` на `Crystal::Path`-receiver,
  вне `initialize`.
- Skip: полиморфные вызовы (`foo.new`, `klass.new`), исключения
  (`raise X.new`), factory-методы (`def self.build`), whitelist путей.
- Config: `allowed` (strings).
- Поведение при наследовании/переопределении: не различаем — работаем
  чисто синтаксически, по receiver-узлу.

### 2. `GodClass` — per-file

Smell: SRP-прокси. Класс, который делает слишком много — метрика, а не
семантика: сообщение называет факты («32 methods, 14 ivars»), не «нарушен
SRP».

- Check: `ClassDef` (не struct, не module) с числом `def` ≥ `max_methods`
  (default 25) ИЛИ instance-var'ов ≥ `max_ivars` (default 10).
- Config: `max_methods`, `max_ivars` (int).

### 3. `DeepInheritance` — per-project

Smell: composition over inheritance. Глубокие цепочки наследования —
хрупкость, скрытые контракты; глубина 3+ почти всегда значит «нужно
композицию».

- Check: видимая глубина цепочки (хопы между классами проекта) ≥ `max_depth`
  (default 2, т.е. флаг при 3+). Issue на нижний класс, сообщение
  перечисляет цепочку (`C < B < A < Base`).
- Skip: внешние родители обрезают цепочку (`MyA < MyB < Kemal::Base` =
  глубина 2); иерархии `Exception`.
- Config: `max_depth`, `allowed_superclasses` (strings; дефолт — stdlib-базы:
  `Exception`, `Reference`, `Object`, `Struct`, `Enum`, `Value`, `IO`).

### 4. `SingleSubclass` — per-project

Smell: speculative hierarchy. База с ровно одним наследником — наследование
«на будущее», которого не случилось.

- Check: не-abstract база, определённая в проекте, с ровно одним subclass'ом.
  Issue на subclass — это он кандидат на композицию (`B` должен *иметь* `A`,
  а не *быть* им).
- Skip: abstract базы (контракт — легитим); внешние базы не считаем.

### 5. `SubclassNoOverride` — per-project

Smell: наследование ради кода, а не полиморфизма. Subclass не переопределяет
ни одного метода родителя — просто «забирает» реализацию.

- Check: пара parent/subclass из индекса, где ни один `def` subclass'а не
  совпадает по имени с не-abstract `def` родителя.
- Skip: родитель внешний; subclass без методов вовсе; сравнение только с
  прямым родителем.

## Порядок работ

1. Каркас: `test_project`-контракт + `Index` + CLI-группа (project_guards.md,
   «Порядок работ»).
2. Per-file: `HardcodedDependency`, `GodClass`.
3. Per-project: `DeepInheritance`, `SingleSubclass`, `SubclassNoOverride`.
4. После каждого этапа: `crystal spec`, самопрогон
   `crystal run src/awesome.cr -- smell src`, `doc <Guard>` глазами.

## Кандидаты на потом (вне scope плана)

- `TooManyIncludes` — класс включает 5+ модулей (mixin-переизпользование,
  беда с `I`-части поверхности) — эвристика, требует калибровки.
- `ModuleUsedOnce` — модуль, включённый одним классом (кандидат на слияние).
- LSP-крошки: override, который только `raise NotImplementedError`, у
  не-abstract родителя.
- Layering (направление зависимостей между слоями) — поверх того же Index,
  но нужен граф вызовов, не только иерархия.
