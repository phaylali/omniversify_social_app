# Reader test fixtures

Real archives the reader tests unpack, both taken from the `koni_rar` test
fixtures in <https://github.com/zenbaku/koni_archive> (MIT, clean-room RAR
implementation). `BookLoader` can read RAR but cannot write it, so a real
container has to live here.

- `synthetic_comic.cbr` — RAR5, three PNG pages plus a `ComicInfo.xml` that
  must not be counted as a page.
- `encrypted_headers.rar` — RAR5 with `-hp` encrypted headers, so opening it
  needs a password; checks the message the reader shows.

`test/book_reader_test.dart` builds its own RAR4 archive (the format classic
`.cbr` comics are in) instead of committing a second binary.
