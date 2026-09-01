# Help incorrectly displays the COMMANDS section

- STATUS: OPEN
- PRIORITY: 100
- TAGS: bug

---

The COMMANDS section should only appear in the root command's help output
(trac -h), since it exists to list available subcommands. Subcommand help
output (e.g. trac ls -h) should not include this section, as it's not
relevant there and just repeats the current command.
