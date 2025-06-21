module _d_paint_cast;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "enum size = " ~ Size ~ ";"
        ~ q{
            class A {}
            final class B: A{}
            
           A ab = new B();
           for (auto cnt = 0; cnt < size; ++cnt)
           {
                B b = cast(B)ab;
           }
        } ~ " }";
}
