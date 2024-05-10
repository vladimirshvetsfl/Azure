New-Item -Path c:\temp -Force -ItemType Directory

New-Item -Path C:\temp\log.txt -ItemType File

Add-Content -Value "This was built with Azure Image Builder" -Path C:\temp\log.txt