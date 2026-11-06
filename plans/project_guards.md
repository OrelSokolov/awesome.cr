# Plan: design-smell guards (group `code`) and per-project analysis

Status: реализовано полностью — каркас (`test_project`, `Awesome::Index`,
CLI-группа `code`) и все guard'ы: per-file `HardcodedDependency`,
`GodClass`; per-project `DeepInheritance`, `SingleSubclass`,
`SubclassNoOverride`. Каталог самих guard'ов группы `code` — в
[code.md](code.md); здесь — per-project часть: контракт
`test_project`, Index и правила работы с внешними родителями.

Исходный вопрос был «можно ли добавить проверки SOLID». Честный разбор по
буквам: **D** (Dependency Inversion) детектируется чисто механически, **S** —
только через прокси-метрики (GodClass), **L** — пара узких случаев, **O** и
**I** требуют того, чего в синтаксическом AST нет (история изменений и
семантика вызовов). Поэтому группа называется `code`, а не `solid` — не
обещаем того, что не проверяем. Как и у существующих guard'ов, принцип:
детектируем факт, а не мнение; не видим — молчим (лучше false negative,
чем false positive).

## Два класса guard'ов

Существующий контракт per-file (`test(source, config)`) остаётся. Для
наследнических проверок иерархия почти всегда раскидана по файлам, поэтому
нужен второй контракт — per-project:

```crystal
abstract class Awesome::Guard
  def test(source : Awesome::Source, config) : Array(Awesome::Issue)
    [] of Awesome::Issue   # базовая реализация: пусто
  end

  def test_project(sources : Array(Awesome::Source), config) : Array(Awesome::Issue)
    [] of Awesome::Issue   # базовая реализация: пусто
  end
end
```

`Guard#test` перестаёт быть abstract (все текущие guard'ы его переопределяют
— ничего не ломается). `Runner#run` после сбора sources вызывает для каждого
guard'а оба метода: `test` по-прежнему по одному source, `test_project` —
один раз со всем набором. Issues у per-project guard'ов всё равно привязаны
к `файл:строка` (определение subclass'а), `Report` не меняется.

`awesome code [paths]` — третья команда-фильтр: `"code"` в `COMMANDS`,
banner и `kind`-фильтр в `CLI.check` (`src/awesome/cli.cr`).

## Index — синтаксический индекс проекта

Per-project guard'ам нужна таблица «класс → superclass», но семантический
проход не нужен: достаточно одного прохода по уже собранным AST. `Runner`
(или отдельный `Awesome::Index`) строит из всех sources:

- для каждого `Crystal::ClassDef` / `Crystal::ModuleDef`:
  квалифицированное имя (стек нейминга файла: `module Foo` + `class Bar` →
  `Foo::Bar`), последний сегмент пути, путь superclass'а как строку
  (`nil` для `Object`/без родителя), `abstract?`, список имён `def`
  (обычных и `abstract def`), файл и строку;
- два вида доступа: точное совпадение по квалифицированному имени и
  multimap по последнему сегменту (для `superclass`, записанного
  относительным путём).

### Разрешение имён — честное ограничение

Парсер не резолвит пути семантически: `class B < Base` внутри `module Foo`
может значить и `Foo::Base`, и топ-левел `Base`. Правила:

1. сначала точное совпадение квалифицированного имени;
2. fallback — единственный кандидат по последнему сегменту;
3. несколько кандидатов или ноль → guard молча пропускает класс
   (неоднозначность = не детектируем, не гадаем).

### Внешние родители (шарды, stdlib)

`lib/**` уже в `DEFAULT_EXCLUDE` (`src/awesome/config.cr`), и
`Runner#collect_files` применяет exclude в том числе к явно переданным
путям — индекс автоматически строится по тому же набору файлов, что и
проверка. Родитель, не найденный в индексе, — «внешний»:

- **DeepInheritance** — считаем только видимые хопы своей цепочки:
  `MyA < MyB < Kemal::Base` = глубина 2;
- **SingleSubclass** — проверяем только базы, определённые в проекте;
- **SubclassNoOverride** — родитель внешний → skip (список методов не знаем).

Whitelist stdlib-баз, наследование от которых легитимно почти всегда:
`Exception`, `Reference`, `Object`, `Struct`, `Enum`, `Value`, `IO` и т.п.
(конфигурируемый список `allowed_superclasses`, дефолт в коде). Иерархии
исключений (`< Exception`) — не флагаем вовсе.

## Guard'ы

### Per-file (не требуют индекса)

**1. `HardcodedDependency`** — `src/awesome/guards/hardcoded_dependency.cr`
- Smell: DIP — класс создаёт зависимости сам (`SomeConcrete.new` в теле
  класса / метода) вместо инъекции через конструктор.
- Check: внутри `ClassDef` — `Call` с именем `new` на константном пути
  (`Crystal::Path`-receiver), не в `initialize`-присваивании поля
  (`@x = X.new` в `initialize` — допустимая форма инъекции не всегда,
  поэтому флагаем только `new` вне `initialize`); сорсы за пределами
  `lib`-типов не различаем — работаем по именам, определённым в проекте
  (совпадение с индексом… нет, per-file: просто все `X.new`, где `X` —
  Path с ≥ 1 сегментом, не из whitelist'а примитивов).
- Skip: `new` без явного типа-пути (`foo.new`, `klass.new` — полиморфизм),
  создание value-типов и исключений (`...Error.new` / `raise X.new`),
  factory-методы (`def self.build`).
- Config: `min_dependencies` (int, default 1 — флагать каждый; или 2,
  решить при реализации), `allowed` (strings — whitelist путей).

**2. `GodClass`** — `src/awesome/guards/god_class.cr`
- Smell: SRP-прокси — класс делает слишком много.
- Check: `ClassDef` (не struct, не module), где `def`-ов ≥ `max_methods`
  (default 25) ИЛИ instance-vars ≥ `max_ivars` (default 10). Флаг на
  определении класса; сообщение называет факт («32 methods, 14 ivars»),
  не «нарушен SRP».
- Skip: `abstract` классы-контракты? — нет, флагаем и их (у них тоже
  бывает ответ одна), но классы, чьё имя кончается на `Controller` и
  подобные суффиксы, не спасать — метрика одинакова для всех.

### Per-project (через Index)

**3. `DeepInheritance`** — `src/awesome/guards/deep_inheritance.cr`
- Smell: composition over inheritance — глубокие цепочки наследования.
- Check: видимая глубина цепочки (хопы между классами, определёнными в
  проекте) ≥ `max_depth` (int, default 2, т.е. флаг при 3+). Issue на
  самый нижний класс цепочки, сообщение перечисляет цепочку
  (`C < B < A < Base`).
- Skip: внешние родители обрезают цепочку (см. выше); `Exception`-иерархии.

**4. `SingleSubclass`** — `src/awesome/guards/single_subclass.cr`
- Smell: speculative hierarchy — база с ровно одним наследником,
  наследование «на будущее».
- Check: класс в индексе, не abstract, имеет ровно одного subclass'а в
  проекте и сам не чей-то override-хелпер. Issue на определение базы
  (или subclass'а — решить при реализации, логичнее на subclass: это он
  кандидат на композицию).
- Skip: база abstract (контракт ради тестов/расширения — легитим);
  родителей-внешних не касаем.

**5. `SubclassNoOverride`** — `src/awesome/guards/subclass_no_override.cr`
- Smell: наследование ради переиспользования кода — subclass ничего не
  переопределяет, только «забирает» реализацию. Кандидат на композицию:
  `B` должен *иметь* `A`, а не *быть* им.
- Check: пара parent/subclass из индекса, где у subclass'а нет ни одного
  `def`, совпадающего по имени с `def` родителя (не-abstract). Issue на
  subclass.
- Skip: родитель внешний; у subclass'а 0 методов вовсе (пустой
  маркер-класс — отдельный случай, не флагаем); цепочки глубже 2 —
  сравнивать с прямым родителем только.

## Wiring

1. `CLI`: `"code"` в `COMMANDS`, banner, `check`-фильтр.
2. `Guard`: не-abstract `test`/`test_project` c пустыми базовыми телами;
   `Runner` — цикл `test_project` после per-file прохода (guard'ы с kind
   `code` в него попадают наравне со всеми: per-project вызов для всех
   зарегистрированных guard'ов, пустой результат у per-file — дёшево).
3. `README.md`: группа в таблицу guard'ов, `awesome code` в usage.
4. `docs/guards/<guard>.md` — как у существующих.
5. `examples/awful/`: один файл на guard (конвенция AGENTS.md: не смешивать
   несколько guard'ов в один файл). Важно: `examples_spec` гоняет Runner
   на директории — пример per-project guard'а должен быть самодостаточен в
   одном файле (иерархия в одном файле = проект из одного файла, индекс
   это покрывает).
6. `spec/`: по файлу на guard. Для per-project — хелпер рядом с
   `guard_issues` в `spec_helper.cr`:

   ```crystal
   def guard_project_issues(guard_class, codes : Array(String), config_yaml = nil)
     sources = codes.map_with_index { |code, i| Awesome::Source.new("(test#{i})", code) }
     # ... test_project(sources, config)
   end
   ```

## Порядок работ

1. Каркас: `test_project`-контракт + `Index` + CLI-группа (без guard'ов).
2. Per-file: `HardcodedDependency`, `GodClass`.
3. Per-project: `DeepInheritance`, `SingleSubclass`, `SubclassNoOverride`.
4. После каждого этапа: `crystal spec`; самопрогон
   `crystal run src/awesome.cr -- code src` на этом репо (self-hosting
   проверка на ложных срабатываниях); `doc <Guard>` глазами.

## Вне scope (осознанно)

- **O (OCP)** — нарушение = «пришлось править существующий код», виден
  только в истории коммитов; прокси через `case .is_a?`-цепочки — шум.
- **I (ISP)** — «модуль включают, но используют 2 метода из 20» —
  требует знать вызовы методов, это семантика.
- Направление зависимостей между слоями (layering) — нужен граф вызовов,
  не только иерархия; возможный follow-up поверх того же Index.
- LSP-контракты — без контрактов в языке нечего проверять.
