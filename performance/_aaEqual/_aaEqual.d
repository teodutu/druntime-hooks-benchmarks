module _aaEqual;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "import aa_utils : GenAA;"
        ~ "enum aa_lit = GenAA!(" ~ Size ~ ", \"" ~ Struct ~ "()\");"
        ~ q{
          static const aa1 = mixin(aa_lit);
          static const aa2 = mixin(aa_lit);
          bool _ = aa1 == aa2;
        }
        ~ " }";
}
