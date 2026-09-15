# Git — Leggi PRIMA di fare danni

Matteo, questo file esiste perché continui a incasinare il repo. Leggilo, seguilo, e smettiamo di perdere tempo a sistemare i tuoi casini.

## Regole base (NON negoziabili)

1. **MAI `git push --force` su un branch condiviso.** Se devi forzare, usa `--force-with-lease` e solo sul TUO branch personale, mai su uno che altri stanno usando.
4. **Prima di iniziare a lavorare**, fai sempre pull o:
   ```
   git checkout main
   git pull
   git checkout -b nome-branch-descrittivo
   ```
5. **Prima di ogni commit**, controlla cosa stai per committare:
   ```
   git status
   git diff --staged
   ```
   Se vedi file che non c'entrano niente col tuo lavoro, STOP. Non committarli. tasto destro sul file "dimentica file"

## Workflow corretto

Pull:
```
git checkout main
git pull
git checkout -b feature/cosa-sto-facendo

# ...lavori...

#Push
git add <file specifici, non "git add ." a caso>
git commit -m "messaggio chiaro di cosa hai fatto"
git push -u origin feature/cosa-sto-facendo
```

## Se hai fatto un casino

**NON improvvisare comandi a caso sperando che si sistemi da solo.** Fermati e:

1. Non fare altri commit/push finché non hai capito cosa è successo.
2. Gira `git status` e `git log --oneline -10` e manda uno screenshot a me o a chat prima di toccare altro.
3. Chiedi PRIMA di usare `reset --hard`, `push --force`, `rebase` o qualsiasi comando che riscrive la storia. Questi comandi possono cancellare lavoro di altri in modo irreversibile.

## Comandi VIETATI senza permesso esplicito

- `git push --force` (su branch condivisi)
- `git reset --hard` (se non sei sicuro al 100% di cosa stai buttando via)
- `git rebase` su branch condivisi
- `git add .` senza aver prima guardato `git status`
- `git checkout -- .` / `git clean -fd` senza aver controllato cosa perdi

## TL;DR

- Ricorda l'ordine preima di fare cazzate 
- Mai forzare push su roba condivisa.
- Nel dubbio, FERMATI e chiedi, invece di tirare a indovinare.