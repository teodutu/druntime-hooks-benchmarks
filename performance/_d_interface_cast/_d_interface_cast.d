module _d_interface_cast;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "enum size = " ~ Size ~ ";"
        ~ q{
            interface I1 {}
            interface I2 {}
            class A : I1, I2 {}
            
           I1 i1 = new A();
           for (auto cnt = 0; cnt < size; ++cnt)
           {
                I2 i2 = cast(I2)i1;
           }
        } ~ " }";
}
