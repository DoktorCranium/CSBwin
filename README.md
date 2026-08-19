CSBWin fork that supports OpenVMS 
Sources based on http://www.dianneandpaul.net/CSBwin/CSBwin_SRC_20230608.7z 


CSBwin is a fan-made, freeware/open-source Windows/Linux engine that recreates FTL Games' classic Dungeon Master
and its sequel/expansion Chaos Strikes Back (the "CSB" in the name), the pioneering 1987 first-person, 
eal-time dungeon-crawler RPGs originally released on the Atari ST.

CSBwin is based on a reverse-engineered source code reconstruction of the Atari ST version created by Paul R. Stevens 
around 2003, which then led to many further ports for modern platforms like Windows and Linux.

It was a serious feat of reverse-engineering — one account describes Stevens as having spent six months, 
roughly eight hours a day, writing around 120,000 lines of what he called "pseudo-C" code to reconstruct
the original engine from scratch, since no original FTL Games source code survived. 
That reconstruction became the foundation both for CSBwin itself and for the broader wave 
of fan ports/remakes of Dungeon Master and Chaos Strikes Back that followed on other platforms.


This fork supports following systems in which it builds and runs

Building: 

OpenVMS 8.4 (AXP) 

''' 
@configure 
@build 
'''


macOS 26.6 
'''
mkdir build 
cd build 
cmake .. 
make -j8 
''' 

Running: 
Dungeon_Master 
Download any Linux tarbal from : 
http://dianneandpaul.net/CSBwin/Games/DungeonMaster_Description.html 

- Copy dungeon.dat and graphics.dat to the CSBwin's executable path and run CSBwin 


Chaos_Strikes_Back
Download any Linux tablall from : 
http://dianneandpaul.net/CSBwin/Games/CSB_Description.html

- Copy dungeon.dat, graphics.dat, hcsb.dat, hcsb.hct and mini.dat to the CSBwin's executable path and run CSBwin 

 
