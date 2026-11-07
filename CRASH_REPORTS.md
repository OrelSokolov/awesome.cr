# CRASH_REPORTS.md

Задокументированные падения `awesome`. Каждый раздел — самодостаточный
кейс: симптом, воспроизведение, стек, корневая причина, предлагаемый
фикс. Используются как прецеденты при развитии чекера.

## CRASH-001: Unhandled `IO::Error: Broken pipe` при закрытии пайпа вывода

- Дата: 2026-11-07
- Версия: 0.3.0 (HEAD `2d7ba94`, также воспроизводится на `dc640c8`;
  скорее всего — любая)
- Серьёзность: средняя. Не портит результаты, но выглядит как краш
  посреди отчёта и возвращает мусорный статус выхода.

### Симптом

При запуске с пайпом, который закрывается раньше конца вывода
(`awesome | head`, `awesome | less` с досрочным выходом, интеграции в
редакторы с ограниченным буфером превью), процесс умирает с unhandled
исключением в произвольном месте печати отчёта. Внешне это выглядит как
«отчёт оборвался на какой-то находке» — в живом случае вывод остановился
после строки-позиции `.../cff/cffinterp.cr:66:5`, до печати сниппета.

### Воспроизведение

```console
$ cd <любой проект с .cr-файлами и находками>
$ bin/awesome 2>err.txt | head -25 > /dev/null
$ head -4 err.txt
Unhandled exception: write (#<IO::FileDescriptor:0x...>): Broken pipe (IO::Error)
  from .../crystal/errno.cr:49:5 in 'unbuffered_write'
  from .../crystal/io/buffered.cr:252:5 in '<<'
  from src/awesome/cli.cr:147:9 in 'run'          # print_report → STDOUT <<
```

### Корневая причина

`CLI.print_report` (src/awesome/cli.cr:142) пишет в `STDOUT` без
обработки `IO::Error`. Когда читатель пайпа закрывается (`head` набрал
строки), очередной `write(2)` возвращает `EPIPE`, Crystal runtime
превращает его в `IO::Error` (сигнал `SIGPIPE` для не-терминального
stdout по умолчанию не игнорируется), исключение всплывает из
буферизованного `<<` и роняет процесс. Точка смерти плавающая — зависит
от того, какая порция вывода первой упёрлась в закрытый пайп, поэтому
кейс маскируется под «обрыв на конкретной находке».

### Фикс (предложение)

Весь вывод отчёта обернуть в обработку EPIPE и выходить тихо:

```crystal
def self.print_report(report : Report) : Nil
  # ... существующая печаль ...
rescue e : IO::Error
  exit(e.os_error == Errno::EPIPE ? 0 : 1)
end
```

либо в точке входа (`bin/awesome.cr`) перехватывать целиком:

```crystal
require "../src/awesome"
begin
  exit Awesome::CLI.run(ARGV)
rescue e : IO::Error
  exit(e.os_error == Errno::EPIPE ? 0 : 1) # читатель ушёл — это не ошибка
end
```

Семантика: EPIPE при записи в stdout — штатная ситуация для CLI
(так же себя ведут rubocop/ameba после явной обработки); любой другой
`IO::Error` остаётся ошибкой.

### Проверка после фикса

```console
$ bin/awesome | head -25 >/dev/null; echo $?   # 0, stderr пуст
$ bin/awesome | less   # выход по q — без трейса на stderr
```

### Статус

Фикс применён (вариант «в точке входа», bin/awesome.cr). Уточнение к
предложению выше: в Crystal 1.21 у `IO::Error` нет `#errno` — errno
доступен через `SystemError#os_error`, т.е. `e.os_error == Errno::EPIPE`.
Кейс стал прецедентом для гарда CliStdoutEpipe
(src/awesome/guards/cli_stdout_epipe.cr): скрипт с выводом на top
level или бинарник из `binaries:` в shard.yml без обработки EPIPE.
