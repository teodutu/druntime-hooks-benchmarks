module _adEq2_equals;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "enum size = " ~ Size ~ ";"
        ~ q{
            class A {
                double[size] d;
                this() { d[] = 1.0; }
            }
            
            A[size] a = new A[size];
            A[size] b = new A[size];

            // Before the change: lowered to `__adEq2`
            // After the change: lowered to `__equals`
            assert(a == b);
        } ~ " }";
}
