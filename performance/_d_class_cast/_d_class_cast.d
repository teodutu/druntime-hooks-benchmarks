module _d_class_cast;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "enum size = " ~ Size ~ ";"
        ~ q{
            class A {}
            class B: A{}
            class C: B{}
            
           A ac = new C();
           for (auto cnt = 0; cnt < size; ++cnt)
           {
                B b = cast(B)ac;
           }
        } ~ " }";
}
