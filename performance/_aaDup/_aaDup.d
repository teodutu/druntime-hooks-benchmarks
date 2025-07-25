module _aaDup;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "import aa_utils : GenAA;"
        ~ "static const aa = mixin(GenAA!(" ~ Size ~ ", \"" ~ Struct ~ "()\"));"
        ~ "auto aa_dup = aa.dup;"
        ~ " }";
}
