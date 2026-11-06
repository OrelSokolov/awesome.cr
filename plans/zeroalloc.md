# Plan: zero-allocations / zero-copy guards

Обнаружение мест, где «просятся» оптимизации по zero allocations / zero copy,
по AST (`Crystal::Parser` — тот же, что использует `awesome` через
`Awesome::Source`). Проверено на Crystal 1.21: все паттерны ниже видны чисто
синтаксически, semantic-анализ не нужен.

Ключевое ограничение: парсер не знает типы (`data[0, 4]` — копия у `String#[]`
или view у `Slice#[]`?). Поэтому guard консервативен по образцу
`StructurePacking`: пропускаем непроверяемое, лучше false negative, чем
false positive.

## Guard 1: `HiddenAllocations` (zero allocations)

`src/awesome/guards/hidden_allocations.cr` + спека
`spec/hidden_allocations_spec.cr` + док `docs/guards/hidden_allocations.md`
(генерировать из констант, как у StructurePacking).

### Паттерн 1: интерполяция внутри `<<` / `puts` / `print`

```crystal
# bad: String.interpolation("a", b, "c") — промежуточная строка
io << "a#{b}c"
puts "x=#{x}"

# good: ноль аллокаций
io << "a" << b
io << "x=" << x
```

Матч: `Crystal::Call(name: "<<"|"puts"|"print", args содержат
Crystal::StringInterpolation)`.

Основа (проверено по компилятору 1.21): `StringInterpolation` разворачивается
в `String.interpolation(...)` — `literal_expander.cr:450-458`; контекст `<<`
промежуточную строку не убирает.

Нюанс: интерполяция из одних `String`/`Char`-литералов
(`"a#{'x'}b"`) — тоже аллокация, предлагать конкатенацию литералов
или просто `io << "a" << 'x' << "b"`.

### Паттерн 2: конкатенация строк в цикле

```crystal
# bad: каждая итерация = новая строка
while line = io.gets
  s += line
end

# good
builder = String::Builder.new
while line = io.gets
  builder << line
end
builder.to_s
```

Матч: `Crystal::OpAssign(op: "+")` или `Crystal::Assign(value:
Call(name: "+"))` над `Var`/`InstanceVar` внутри `Crystal::While` /
`Crystal::Block` от `each`/`times`/`loop`/`repeat`/`map`.

Тип string не виден — считаем строкой, если справа литерал (`s += "x"`)
или правая часть `+` содержит строковый литерал. Иначе пропускаем.

### Паттерн 3: промежуточный массив ради проверки

```crystal
# bad: аллоцирует Array ради size
xs.select { |x| x > 1 }.size == 0
xs.map { |x| x * 2 }.empty?

# good
xs.none? { |x| x > 1 }
xs.empty?  # если блок без условий — просто empty? на исходной коллекции
```

Матч: `Call(name: "size"/"empty?")` с obj = `Call(name: "select"/"reject"/"map")`.
Подсказывать замену `size == 0` → `none?`, `size > 0` → `any?`
(само сравнение с литералом — соседний `Call` с `==`/`>`/`>=`/`<`).

### Паттерн 4: `def to_s : String` вместо `def to_s(io : IO)`

```crystal
# bad: каждый вызывающий аллоцирует строку
def to_s : String
  "#{@x}"
end

# good
def to_s(io : IO)
  io << @x
end
```

Матч: `Crystal::Def(name: "to_s", args: [])` — независимо от return type.
Не фаерить на `def to_s` внутри `struct`/`class` с `@[Format]`-аннотациями?
Нет — наоборот, оверрайд безаргументного `to_s` мешает `io << obj` везде.
Пропускать только `def to_s!`-подобное не нужно (такого нет).

Конфиг (`awesome.yml`), по аналогии с `check_extern`:

```yaml
HiddenAllocations:
  check_to_s: true   # паттерн 4 отдельно отключаемый (стилевой спор)
```

## Guard 2: `ZeroCopyStreaming` (zero copy)

`src/awesome/guards/zero_copy_streaming.cr` + спека + док.

Только паттерны, где тип очевиден из самого вызова (без type info):

### Паттерн 5: `File.read(...)` ради построчного обхода

```crystal
# bad: весь файл в память, потом строки ещё раз
File.read(path).each_line { |l| ... }
File.read(path).split("\n")

# good: стриминг, константная память
File.each_line(path) { |l| ... }
```

Матч: `Call(name: "each_line"/"each_line_with_separator"/"split"/"lines",
obj: Call(name: "read", obj: Path(File)))`. То же для `IO#gets_to_end`
в паре с `split`/`each_line` — матч `Call(split/each_line, obj:
Call(name: "gets_to_end"))`.

### Явно НЕ проверяем (нет типов → false positives)

- `dup` / `clone` / `to_a` / `String#[]`-подстроки — тип выражения не виден.
- Если захочется покрыть — это уже не syntax-уровень, а semantic
  (`Crystal::Compiler` программно) — отдельная большая тема, вне плана.

## Идея 2.x (после основных): `@[ZeroAlloc]` аннотация

Юзер помечает хот-путь:

```crystal
@[ZeroAlloc]
def encode_header(io, req)
  io << req.path  # ок
  log.debug { "#{req}" }  # guard: интерполяция внутри ZeroAlloc-метода
end
```

Guard (расширение `HiddenAllocations` или отдельный `ZeroAllocPath`):
внутри def с аннотацией `@[ZeroAlloc]` фаерить на любой вызов из
известно-аллоцирующих (`String.interpolation` — интерполяции, `.dup`,
`.clone`, `String.build`, `Array.new`, `Hash.new`, `to_a`, `.new` на
референс-типах из stdlib-белого списка) + на паттерны 1–3 выше.
Парсинг аннотаций уже умеем: `StructurePacking::Visitor#visit(Expressions)`
собирает их через object_id.

Это и есть «где просятся оптимизации» наоборот: не линтер угадывает хот-пути,
а код их декларирует.

## Примеры `examples/` — bad-фикстуры на каждый случай

В репозитории появляется каталог `examples/` с примерами, на которых guards
файрят — по одному файлу на каждый паттерн. Это и живая документация, и
материал для спек, и способ проверить линтер на «настоящем» коде (в примере
может быть несколько строк вокруг, а не голый сниппет).

Структура:

```
examples/
  hidden_allocations/
    interpolation_in_append.cr   # паттерн 1: io << "a#{b}c"
    interpolation_in_puts.cr     # паттерн 1: puts "x=#{x}"
    string_concat_in_loop.cr     # паттерн 2: s += line в while
    select_for_size.cr           # паттерн 3: xs.select { }.size == 0
    to_s_without_io.cr           # паттерн 4: def to_s : String
  zero_copy_streaming/
    file_read_each_line.cr       # паттерн 5: File.read(p).each_line
    file_read_split.cr           # паттерн 5: File.read(p).split("\n")
```

Требования к примерам:

- Каждый файл — самодостаточный кусок кода (парсится `Crystal::Parser` без
  ошибок; компилироваться при этом не обязан — типов-аргументов может не
  быть, `Crystal::Parser` их не требует).
- Внутри файла — комментарий с номером паттерна и ожидаемым issue
  (guard name + примерный текст), чтобы пример был самодокументируемым.
- В примере допустим «шумовой» окружающий код — проверяем, что guard
  фаерит на нужной строке и не фаерит на соседней нормальной.
- Спеки guard'ов гоняют и инлайн-сниппеты, и файлы из `examples/`
  (`Awesome::Source.new(path)`) — так фиксируется, что линтер срабатывает
  на реальных файлах, а не только на голых выражениях.
- Прогон всего `examples/` — часть проверки перед релизом: ожидаемое
  количество issues известно из комментариев, регрессия видна сразу.

## Честная граница метода

AST-линтер ловит идиомы, а не фактические аллокации. Настоящая верификация
zero-alloc — рантайм (счётчики GC, `--emit llvm-ir` анализ call-графа) —
в план не входит, упоминать в доке guards.

## Порядок работ

1. Каталог `examples/` с bad-фикстурами (по файлу на паттерн, см. раздел
   «Примеры examples/») + спека, прогоняющая guard по всем файлам каталога.
2. Guard 1 паттерн 1 (интерполяция в `<<`) — самый ценный, минимум ложных
   срабатываний → спеки → док.
3. Паттерны 2–4 с конфигом `check_to_s`.
4. Guard 2 (стриминг `File.read`).
5. README/`awesome.yml` example, прогон на самом `awesome.cr`
   (`crystal run src/awesome.cr -- lint .`? — проверить CLI-инвокацию)
   и на каком-нибудь реальном шарде (spec/dependencies) — замерить
   false positive rate.
6. (Опционально) `@[ZeroAlloc]`.
