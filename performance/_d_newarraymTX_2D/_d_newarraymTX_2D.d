module _d_newarraymTX_2D;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ Struct ~ "[][] a = new " ~ Struct ~ "[][](" ~ Size ~ "," ~ Size ~ ");"
        ~ "}";
}
