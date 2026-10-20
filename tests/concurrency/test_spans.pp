{ Консольний раннер fpcunit-тестів модуля spans (TSpan/TReadOnlySpan).
  Ті самі тести входять до packages/rtl-objpas/tests/testrunner.rtlobjpas.pp.
  Збірка: tests/concurrency/build-spans.sh }
program test_spans;

{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  consoletestrunner, utcspans;

var
  App: TTestRunner;
begin
  DefaultFormat := fPlain;
  DefaultRunAllTests := True;
  App := TTestRunner.Create(nil);
  App.Initialize;
  App.Title := 'spans tests';
  App.Run;
  App.Free;
end.
