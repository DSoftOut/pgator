module pgator.test.vibe_rest;

version(IntegrationTest)
void vibedRESTEmulationTests(string httpUrl)
{
    import vibe.web.rest;

    struct S1
    {
        string v1;
        long v2;
    }

    interface ITest
    {
        string getEchoText(string value_for_echo);
        long getEchoBigint(long value_for_echo);
        long postEchoBigint(long value_for_echo);
        double getEchoFloat8(double value_for_echo);
        double postEchoFloat8(double value_for_echo);

        S1 postRest1(string value1, long value2);

        void getUndefinedMethod(); // always returns error
    }

    auto m = new RestInterfaceClient!ITest(httpUrl);

    assert(m.getEchoText("abc") == "abc");
    assert(m.getEchoBigint(123456) == 123456);
    assert(m.postEchoBigint(123456) == 123456);
    assert(m.getEchoFloat8(123.45) == 123.45);
    assert(m.postEchoFloat8(123.456789) == 123.456789);

    S1 s1 = {v1: "abc", v2: 123};
    assert(m.postRest1(s1.v1, s1.v2) == s1);

    // REST exception check
    {
        bool catched = false;

        try m.getUndefinedMethod();
        catch(Exception e)
        {
            catched = true;
        }

        assert(catched);
    }
}
