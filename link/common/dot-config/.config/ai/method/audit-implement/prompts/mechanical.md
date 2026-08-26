ALREADY CHECKED MECHANICALLY. `clerk lint` ran over this whole diff before you started, so do not re-report what it covers:
- Comments naming code by plan position or citing a ticket id — covered completely. Do not hunt for them.
- Sibling scenario tests that belong under one umbrella, and a method living apart from the file declaring its type — covered only for the shapes it can see. It matches lines rather than declarations, so a type inside a grouped `type ( ... )` block or a generic `type Box[T any]` is invisible to it. Report one of those yourself; it will not have been.
