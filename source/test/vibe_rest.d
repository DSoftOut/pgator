module pgator.test.vibe_rest;

version(IntegrationTest)
void vibedRESTEmulationTests(string httpUrl)
{
    import vibe.web.rest;

    interface ITest
    {
        string getEchoText(string value_for_echo);
        long getEchoBigint(long value_for_echo);
        long postEchoBigint(long value_for_echo);
        double getEchoFloat8(double value_for_echo);
        double postEchoFloat8(double value_for_echo);
    }

    auto m = new RestInterfaceClient!ITest(httpUrl);

    assert(m.getEchoText("abc") == "abc");
    assert(m.getEchoBigint(123456) == 123456);
    assert(m.postEchoBigint(123456) == 123456);
    assert(m.getEchoFloat8(123.45) == 123.45);

    //assert(m.getEchoBigint(123.456) == 123.456); //TODO: causes error, need to check this case
    //assert(m.postEchoFloat8(123.45) == 123.45); //TODO: POST support
}
