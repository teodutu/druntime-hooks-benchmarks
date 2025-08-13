module _d_newarrayiT;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void* dummy" ~ Struct ~ '_' ~ Size ~ ";"
        ~ "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "struct S{char[" ~ Size ~ "]a = 1;};"
        ~ "S[] a = new S[" ~ Size ~ "];"
        ~ "dummy" ~ Struct ~ '_' ~ Size ~ " = a.ptr;"
        ~ "}";
}
