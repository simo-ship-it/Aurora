import Foundation

// Le prove di Aurora. Si eseguono con `swift run AuroraCheck` e restituiscono
// un codice d'uscita diverso da zero se qualcosa non torna, così l'integrazione
// continua se ne accorge da sola.

runBlockTests()
runInlineTests()
runEditingTests()
exit(Check.report())
