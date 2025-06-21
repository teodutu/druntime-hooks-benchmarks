module _d_dynamic_cast;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "enum size = " ~ Size ~ ";"
        ~ q{
            interface I {}
            class A {}
            class B: A, I {}
            
           A ab = new B();
           for (auto cnt = 0; cnt < size; ++cnt)
           {
                I i = cast(I)ab;
           }
        } ~ " }";
}
