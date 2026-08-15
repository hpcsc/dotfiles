**Do NOT run `git commit` via Bash.** Use the Skill tool.

Invoke the skill `clerk prepare` named in `commit_skill`, passing the task description and any ticket context carried in the request. It is `commit` where the repo defines its own — usually to carry a convention its history depends on, a ticket trailer or a scope prefix — and `pcommit`, which delegates to the same agent, where it does not.
