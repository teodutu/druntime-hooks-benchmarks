module _d_arrayassign;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest ="void test" ~ Struct ~ '_' ~ Size ~ "Elems() {"
    ~ Struct ~ "[" ~ arr ~ ".length] a;"
    ~ "a = " ~ arr ~ ";"
    ~"}";
}
