Your lens is DESIGN: the types, fields, methods and exported names that this change adds or changes, and the words they use. Judge the design on its own merits. Do not judge it by how close it stays to a planned design: a planned design is a first guess, and the code can be right where the plan was wrong.

Start with the design view. Run `clerk design show --changes` when a run is open on this branch, else `clerk design show --base <the base of the diff>`. It lists the exported names and who outside the package uses each one, draws the new and changed types, and groups the parameters that functions pass together. Read the code behind a box before you raise anything about it.

Raise a finding when one of these holds, and name what it costs:

- A type holds two concepts: two groups of fields that no method uses together. Name both groups.
- Data and the behaviour that uses it live apart: a function reads or writes the fields of another type more than its own. Name the function and the type that owns the data.
- A type grows into the centre of the change, so that most new code depends on it and each task adds to it. Or a type has fields and no behaviour, and callers change it from outside.
- The same values travel through three or more functions as parameters. They want a type of their own.
- An embedded type puts methods into the outer type's API that no caller needs, where a field would contain it.
- A dependency points the wrong way: a lower-level package imports a higher-level one.
- An exported name has no caller outside its package, and no reason for it is recorded.

Weigh every new or renamed name against {{naming_guide}}: one word for two concepts or two words for one, a formal word where a plain one exists, a metaphor, or a method name that does not read as a sentence with its receiver. The language's naming-patterns guideline governs the structure of package, interface and constructor names. Set `quality_kind: "naming"` for a name and `quality_kind: "structure"` for the rest.

Required reading: {{reading}}. {{disclosure}}

A preference that you cannot tie to a cost or to a guideline is not a finding. CORRECTNESS IS NOT YOURS: put a wrong condition or an unhandled error in `note`. How code is split into files, and how comments read, belong to the guidelines lens.
