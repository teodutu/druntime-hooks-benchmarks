module _d_arrayappendcTX;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { " ~ q{
        } ~ Struct ~ "[] a;" ~ q{
        } ~ "a.reserve(" ~ Size ~ "); }";
}
