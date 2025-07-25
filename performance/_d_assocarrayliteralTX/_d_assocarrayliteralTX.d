module _d_assocarrayliteralTX;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "import aa_utils : GenAA;"
        ~ "auto aa = mixin(GenAA!(" ~ Size ~ ", \"" ~ Struct ~ "()\"));"
        ~ " }";
}
