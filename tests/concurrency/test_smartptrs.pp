{ Консольний раннер fpcunit-тестів модуля smartptrs (TScoped/TArc/TWeak).
  Ті самі тести входять до packages/rtl-objpas/tests/testrunner.rtlobjpas.pp.
  Збірка: tests/concurrency/build-smartptrs.sh }
program test_smartptrs;

{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  consoletestrunner, utcsmartptrs;

var
  App: TTestRunner;
begin
  DefaultFormat := fPlain;
  DefaultRunAllTests := True;
  App := TTestRunner.Create(nil);
  App.Initialize;
  App.Title := 'smartptrs tests';
  App.Run;
  App.Free;
end.
