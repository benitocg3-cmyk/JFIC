# Developpement sous Windows 11

## Prerequis

- Windows 11 x64 ;
- Visual Studio 2022 ou le SDK .NET 9 ;
- acces NuGet au premier restore ;
- Node.js facultatif pour le smoke-test Web.

## Construire le ZIP Ubuntu

Depuis la racine du projet :

```powershell
.\eng\Package-Ubuntu.ps1
```

Le fichier produit est :

```text
dist\JellyfinImageControls-Ubuntu-1.0.0-beta2.zip
```

Il contient la DLL JFIC, les assets Web optionnels et les scripts Ubuntu.

## Installation recommandee

Copiez le ZIP avec le Bureau a distance dans `~/jfic-install` sur Ubuntu,
decompressez-le, puis suivez
[le guide Ubuntu](UBUNTU-SAFE-INSTALL.md). C'est la methode recommandee car
elle ne depend pas de SSH ni du mot de passe SSH.

## Installation SSH facultative

```powershell
.\eng\Remote-Ubuntu.ps1 -HostName 192.168.1.93 -User ben -Action Install
```

Le script envoie le ZIP, verifie son SHA-256, puis lance `install.sh` avec
`sudo`. Le mot de passe SSH et le mot de passe sudo sont saisis dans la
session ; ils ne sont pas stockes.

Actions utiles :

```powershell
.\eng\Remote-Ubuntu.ps1 -HostName 192.168.1.93 -User ben -Action NvidiaPreflight -SkipBuild
.\eng\Remote-Ubuntu.ps1 -HostName 192.168.1.93 -User ben -Action Doctor -SkipBuild
.\eng\Remote-Ubuntu.ps1 -HostName 192.168.1.93 -User ben -Action Verify -SkipBuild
.\eng\Remote-Ubuntu.ps1 -HostName 192.168.1.93 -User ben -Action Uninstall -SkipBuild
```

`Permission denied` avant l'affichage de `id` signifie que le compte ou le
mot de passe SSH est refuse. Si `id` fonctionne puis que `sudo -v` echoue,
le compte n'a pas le droit sudo ou le mot de passe sudo est incorrect.

Test minimal :

```powershell
ssh -tt -p 22 ben@192.168.1.93 "id && sudo -v"
```

## Boucle de test

1. Construire `Package-Ubuntu.ps1`.
2. Copier le ZIP par Bureau a distance.
3. Executer `sudo bash install.sh`.
4. Tester puis executer `sudo bash doctor.sh`.
5. En cas de probleme, executer `sudo bash uninstall.sh`.

JFIC ne demande aucune edition de `/usr/share/jellyfin/web`,
`/etc/default/jellyfin` ou du service systemd.
