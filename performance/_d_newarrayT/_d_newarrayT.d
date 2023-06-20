module _d_newarrayT;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ Struct ~ "[] a = new " ~ Struct ~ "[" ~ Size ~ "]; }";
}
