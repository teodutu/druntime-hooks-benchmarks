module _d_arrayappendT;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { " ~ Struct ~ "[] a; a ~= " ~ arr ~ "; }";
}
