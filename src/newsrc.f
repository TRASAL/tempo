c      $Id$
	subroutine newsrc(nits,jits,nboot)

	implicit real*8 (A-H,O-Z)
	character DECSGN*1,path*160
	character*1 ctmp, dtmp
	include 'dim.h'
	include 'acom.h'
	include 'bcom.h'
	include 'trnsfr.h'
	include 'clocks.h'
	include 'dp.h'
	include 'orbit.h'
	include 'eph.h'
	include 'glitch.h'

	if(jits.ne.0) goto 30

C  Zero out all input parameters and fit coefficients.
	call zeropar(nits)      

	if(oldpar)then

C  Columns:                 1 ... 25       27   29    33   34   40   42
	   read(50,1010) (nfit(i),i=1,25),nbin,nprnt,nits,iboot,ngl,nddm,
C                44    46     47      51 ... 60
     +   	nclk,nephem,ncoord,(nfit(i),i=26,35)
 1010	   format(25z1,1x,z1,1x,i1,3x,i1,z1,4x,3i2,1x,2i1,3x,10i1)

C  Set nfit(k) = 1 if the k'th parameter is to be fit for
C  If nfit(1) > 1 then no fit is done, but tz2.tmp is created
C  Set nprnt = 1, 2, ... to list every 10, 100, ... TOAs in output file
C  Set nits = max no of iterations (9 ==> iterate until convergence)

C nbin  Binary pulsar model		nclk	Reference time scale
C--------------------------------------------------------------------
C   1 	Blandford-Teukolsky		  0	Uncorrected
C   2	Epstein-Haugan			  1	UTC(NIST)
C   3	Damour-Deruelle			  2	UTC
C   4	DDGR				  3	TT(BIPM)
C   5	H88				  4	(PTB)
C   6	BT+				  5	AT1
C   7	DDT
C   8   DDP
C   9	BT, 2 orbits
C   a	BT, 3 orbits

C  Get initial parameter values from lines 2-4 of data file
	   read(50,1020) psrname,pra,pdec,pmra,pmdec,rv,p0,p1,pepoch,p2,px,dm
 1020	   format(a12,8x,f20.1,f20.1,3f10.0/1x,d19.9,2d20.6,2d10.0/
     +  	8x,f12.0)

	   if(nbin.ne.0) read(50,1030) a1(1),e(1),t0(1),pb(1)
 1030	   format(4f20.0)
	   if(nbin.ne.0.and.nbin.ne.7) read(50,1031) omz(1),omdot,gamma,
     +         pbdot,si,am,am2,dr,dth,a0,b0
 1031	   format(6f10.0,f6.0,3f4.3,f2.1)
	   if(nbin.eq.7) read(50,1032) omz(1),omdot,gamma,pbdot,
     +         si,am,am2,bp,bpp
 1032	   format(7f10.0,2f5.0)

	   if(nbin.ge.9) then	!Read params for 2nd and 3rd orbits
	      do i=2,nbin-7
		 read(50,1030) a1(i),e(i),t0(i),pb(i)
		 read(50,1031) omz(i)
	      enddo
	   endif
c Convert PB to days if greater than 3600 (ie min Pb for old style = 1h)
	   do i=1,3
	      if(pb(i).gt.3600.d0)pb(i)=pb(i)/86400.d0
	   enddo

	   if(ngl.ne.0)then
	      do i=1,ngl
		 read(50,1035)(nfit(60+(i-1)*NGLP+j),j=1,NGLP),glepoch(i),
     +	            glph(i),glf0p(i),glf1p(i),glf0d1(i),gltd1(i)
		 if((nfit(60+(i-1)*NGLP+4).ne.0.or.nfit(60+(i-1)*NGLP+5).ne.0)
     +                 .and.gltd1(i).eq.0.d0)then
		    write(0,*)' WARNING: Exp term requested but gltd1 = 0; set = 1.0d'
		    gltd1(i)=1.d0
		 endif
	      enddo
	   endif
 1035	   format(5i1,5x,6f12.0)

c         calculate header lines to be skipped when reading TOAs
          nskip=4
          if(nbin.gt.0) nskip=6
          if(nbin.ge.9) nskip=6 + 2*(nbin-8)
          if(ngl.gt.0)  nskip=nskip+ngl

	else
	   call rdpar(nits)
	   if (parunit.eq.49) nskip = 0  ! separate par file
	endif

	if(gro)nits=1
	if(xitoa)nclk=2                  ! Force correction to UTC for ITOA output

C Convert units
	p1=p1*1.d-15
	p2=p2*1.d-30
	dr=dr*1.d-6
	dth=dth*1.d-6
	a0=a0*1.d-6
	b0=b0*1.d-6
	pbdot=pbdot*1.d-12
	xpbdot=xpbdot*1.d-12
	xdot=xdot*1.d-12
	edot=edot*1.d-12

	if(pepoch.gt.2400000.5d0) pepoch=pepoch-2400000.5d0
	ndmcalc=max(nfit(16),ndmcalc)

	pra=ang(3,pra)			!Convert to radians
	pdec=ang(1,pdec)

	if(ncoord.eq.0)then
	   pmra=pmra*1d-1
	   pmdec=pmdec*1d-1
	   px=px*1d-3
	   call fk4tofk5(pra,pdec,pmra,pmdec,px,rv)
	   pmra=pmra*1d1
	   pmdec=pmdec*1d1
	   px=px*1d3
	   write(31,1036)
 1036	   format(' Input B1950 coords converted to J2000')
	endif

	if(f0.eq.0.)f0=1.d0/p0
	if(f1.eq.0.)f1=-p1/p0**2
	if(f2.eq.0..and.p2.ne.0)then
	   f2=(2.d0*p1*p1 - p2*p0)/(p0**3)
	endif

	nboot=0
	if(iboot.gt.0) nboot=2**iboot

c  Open ephemeris file
	if(nephem.lt.1.or.nephem.gt.kephem)stop 'Invalid ephemeris nr'
	kd=index(ephdir,' ')-1
	kf=index(ephfile(nephem),' ')-1
	path=ephdir(1:kd)//ephfile(nephem)(1:kf)
	call ephinit(44,path)

C Open .par file
	k=index(psrname,' ')-1
	path=psrname(1:k)//'.par'
	open(71,file=path,status='unknown')

C  Check to make sure selected parameters are consistent with model
	if(nbin.eq.0) then
	  do 1 I = 9, 15
1	  nfit(I) = 0
	  nfit(18) = 0
	  do 11 i=20,35
11	  nfit(i)=0
	endif

	if (nbin .eq. 1) then
	  do 2 I = 20, 23
2	  nfit(I) = 0
	endif

	if(nbin.eq.2) then
	  do 21 i=21,23
21	  nfit(i)=0
	endif

	if(nbin.eq.4) then
	  nfit(15)=0
	  nfit(20)=0
	  nfit(23)=0
	endif

	if(t0(1).lt.39999.5d0) t0(1)=t0(1)+39999.5d0  !Convert old style to MJD
	if(t0(2).lt.39999.5d0) t0(2)=t0(2)+39999.5d0
	if(t0(3).lt.39999.5d0) t0(3)=t0(3)+39999.5d0

	if (oldpar) then	! in old style files, xomdot and xpbdot
	  xomdot=0.		!    replaced omdot and pbdot in value and
	  xpbdot=0.		!    flag fields in the header.
	  if(nbin.eq.4) then
	    xpbdot=pbdot
	    xomdot = omdot
	    omdot = 0.
	    pbdot = 0.
	    if (nfit(14).eq.1) then
	      nfit(14)=0
	      nfit(37)=1
	    endif
	    if (nfit(18).eq.1) then
	      nfit(18)=0
	      nfit(38)=1
	    endif
	  endif
	endif

	if (nfit(3).gt.12) then
	  write (*,*) "Error: maximum of 12 frequency derivatives allowed"
	  stop
	endif

C Read clock corrections
	if(nclk.gt.0)then
	   kc=index(clkdir,' ')-1                     ! Obs to NIST
	   path=clkdir(1:kc)//clkfile(1)
	   open(2,file=path,status='old',err=900)
	   read(2,450)		                      !Skip header lines
	   read(2,450)
 450	   format(a1)
	   do 451 i=1,NPT-1	                      !Read the whole file
	      read(2,1451,end=452) tdate(i),xlor,xjup,ctmp,dtmp
 1451	      format(f9.0,2f12.0,1x,a1,1x,a1)
	      jsite(i) = 99
	      call upcase(ctmp)
	      call upcase(dtmp)
	      if (ctmp.ge.'0' .and. ctmp.le.'9') jsite(i) = ichar(ctmp)-48
	      if (ctmp.ge.'A' .and. ctmp.le.'Z') jsite(i) = ichar(ctmp)-55
	      if (ctmp.eq.'@') jsite(i) = -1
	      if(xlor.gt.800.d0) xlor=xlor-818.8d0
	      ckcorr(i)=xjup-xlor
	      ckflag(i) = 0
	      if (dtmp.eq.'F') ckflag(i) = 1        ! "fixed" -- no interpolation
 451	   continue
	   i=NPT
	   k=index(clkfile(1),' ')-1
	   write(*,'(''WARNING: '',a,'' too long, not all read'')')
     :  	clkfile(1)(1:k)
 452	   ndate=i-1
	   close(2)
	endif

	if(nclk.eq.2)then                           ! NIST to UTC
	   path=clkdir(1:kc)//clkfile(2)            
	   open(2,file=path,status='old',err=900)
	   read(2,1090)
	   read(2,1090)
	   do 23 i=1,NPT
	      read(2,1091,end=24) tutc(i),utcclk(i)
	      utcclk(i)=0.001d0*utcclk(i)
 23	   continue
	   k=index(clkfile(2),' ')-1
	   write(*,'(''WARNING: '',a,'' too long, not all read'')')
     :  	clkfile(2)(1:k)
 24	   tutc(i)=0.
	   close(2)
	endif

	if(nclk.ge.3) then                          ! NIST to other
	   path=clkdir(1:kc)//clkfile(nclk)
	   open(2,file=path,status='old',err=900) 
	   read(2,1090)
	   read(2,1090)
 1090	   format(a1)
	   do 90 i=1,NPT-1
	      read(2,1091,end=92) tbipm(i),bipm(i)
 1091	      format(f10.0,f19.0)
	      bipm(i)=0.001d0*bipm(i)
 90	   continue
	   i=NPT
	   k=index(clkfile(nclk),' ')-1
	   write(*,'(''WARNING: '',a,'' too long, not all read'')')
     :         clkfile(nclk)(1:k)
 92	   tbipm(i)=0.
	   close(2)
	endif

c  Beginning of iteration loop

 30	write(31,'(/)')
	if(nits.gt.1)write(31,1038)jits+1,nits
 1038	format('Iteration',i3,' of',i3/)

	p0=1.d0/f0
	p1=-f1/f0**2
	if(si.gt.1.d0) si=1.d0

	call radian (pra,irh,irm,rsec,123,1)
	call radian (pdec,idd,idm,dsec,1,1)
	decsgn=' '
	if(pdec.lt.0.) decsgn='-'
	idd=iabs(idd)

	write(31,1039) bmodel(nbin),nbin,nddm
1039	format('Binary model: ',a,' nbin: ',i2,'   nddm:',i2)
	if(psrframe)write(31,'(''Parameters in pulsar frame'')')
	irs=rsec
	rsec=rsec-irs
	ids=dsec
	dsec=dsec-ids
	write(31,1040) psrname,irh,irm,irs,rsec,decsgn,idd,idm,ids,dsec,
     +    f0,p0,f1,p1*1.d15,f2,f3
1040	format (/'Assumed parameters -- PSR ',a12//
     +  'RA: ',11x,i2.2,':',i2.2,':',i2.2,f9.8/
     +  'DEC:',10x,a1,i2.2,':',i2.2,':',i2.2,f9.8/
     +  'F0 (s-1): ',f22.17,6x,'(P0 (s):',f24.19,')'/
     +  'F1 (s-2): ',1p,d22.12,0p,6x,'(P1 (-15):',f22.12,')'/
     +  'F2 (s-3): ',1p,d22.9/'F3 (s-4): ',d22.6,0p)
         do i = 1, 6
	   if (f4(i).ne.0)write(31,1045)i+3,-i-4,f4(i)
 1045	   format ('F',i1,' (s',i2,'): ',1p,d22.9)
         enddo
         do i = 7, 9
	   if (f4(i).ne.0)write(31,1046)i+3,-i-4,f4(i)
 1046	   format ('F',i2,' (s',i3,'): ',1p,d22.9)
         enddo
	 write (31,1047) pepoch, dm
 1047	 format ('Epoch (MJD):',f20.8/'DM (cm-3 pc):',f19.6)
	do i = 1, ndmcalc-1
	   write (31,1048) i, dmcof(i)
	enddo
 1048	format ('DMCOF',i1,':',1p,d25.9)

	if(pmra.ne.0.0)write(31,'(''PMRA (mas/yr):'',f18.4)')pmra
	if(pmdec.ne.0.0)write(31,'(''PMDEC (mas/yr):'',f17.4)')pmdec
	if(px.ne.0.0)write(31,'(''Parallax (mas):'',f17.4)')px

	if(a1(1).ne.0.d0) write(31,1050) a1(1),e(1),t0(1),pb(1),omz(1)
1050	format('A1 sin(i) (s):',f18.9/'E:',f30.9/'T0 (MJD):',f23.9/
     +    'PB (d):',f25.12/'Omega0 (deg):',f19.6)
	if(omdot.ne.0.0)write(31,'(''Omegadot (deg/yr):'',f14.6)')
     +      omdot
	if(xomdot.ne.0.0)write(31,'(''XOMDOT (deg/yr):'',f16.3)')
     +      xomdot
	if(pbdot.ne.0.0)write(31,'(''PBdot (-12):'',f20.3)')1.d12*pbdot
	if(xpbdot.ne.0.0)write(31,'(''XPBDOT (-12):'',f19.3)')1.d12*xpbdot
	if(gamma.ne.0.0)write(31,'(''Gamma (s):'',f22.6)')gamma
	if(si.ne.0.0)write(31,'(''sin(i):'',f25.6)')si
	if(am.ne.0.0)write(31,'(''M (solar):'',f22.6)')am
	if(am2.ne.0.0)write(31,'(''m2 (solar):'',f21.6)')am2
	if(dr.ne.0.0)write(31,'(''dr (-6):'',f24.3)')1.d6*dr
	if(dth.ne.0.0)write(31,'(''dth (-6):'',f23.3)')1.d6*dth
	if(a0.ne.0.0)write(31,'(''A0 (-6):'',f24.3)')1.d6*a0
	if(b0.ne.0.0)write(31,'(''B0 (-6):'',f24.3)')1.d6*b0
	if(bp.ne.0.0)write(31,'(''bp:'',f29.6)')bp
	if(bpp.ne.0.0)write(31,'(''bpp:'',f28.6)')bpp
	if(xdot.ne.0.0)write(31,'(''Xdot (-12):'',f21.6)')1.d12*xdot
	if(edot.ne.0.0)write(31,'(''Edot (-12 s-1):'',f17.6)')1.d12*edot

	if(nbin.ge.9) write(31,1051) a1(2),e(2),t0(2),pb(2),omz(2)
1051	format('X(2) (s):',f23.7/'E(2):',f27.9/'T0(2) (MJD):',f20.9/
     +    'Pb(2) (d):',f22.6/'Om(2) (deg):',f20.6)
	if(nbin.eq.10) write(31,1052) a1(3),e(3),t0(3),pb(3),omz(3)
1052	format('X(3) (s):',f23.7/'E(3):',f27.9/'T0(3) (MJD):',f20.9/
     +    'Pb(3) (d):',f22.6/'Om(3) (deg):',f20.6)

	if(ngl.gt.0)then
	  do i=1,ngl
	    write(31,1053)i,glepoch(i),glph(i),glf0p(i),
     :        glf1p(i),glf0d1(i),gltd1(i)
	  enddo
	endif
1053	format('Glitch',i2/'  Epoch (MJD):',f18.6/
     :    '  dphs:',f25.6/'  df0p (s-1):',1p,d19.7/
     :    '  df1p (s-2):',d19.7/
     :    '  df0d1 (s-1):',d18.7,0p/'  td1 (d):',f22.5)

	if (nbin.gt.0)then
	   do i=1,3
	      pb(i)=pb(i)*86400.d0
	   enddo
	endif
	k=0
	nfit(1)=1
	if(nfit(3).ge.2) nfit(4)=1

	do 70 i=1,38				!Set up parameter pointers
	if(nfit(i).eq.0) go to 70
	k=k+1
	mfit(k)=i
70	continue

	if(nfit(3).ge.3) then			!Pointers to Fn coeffs
	  do i=1,nfit(3)-2
	     k=k+1
	     mfit(k)=50+i
	     nfit(50+i)=1
	  enddo
	endif

	if(nfit(16).ge.2) then			!Pointers to DM coeffs
	  do i=1,nfit(16)-1
	     k=k+1
	     mfit(k)=40+i
	     nfit(40+i)=1
	  enddo
	endif

	if(ngl.ne.0)then
	  do i=61,60+NGLT*NGLP
	    if(nfit(i).ne.0)then
	      k=k+1
	      mfit(k)=i
	    endif
	  enddo
	endif

	nparam=k
	write(31,1060) nparam
1060	format(/'Fit for',i3,' parameters, including phase.')

	return

 900	write(*,'(''Failed to open clock correction file: '',a)')path
	STOP

	end
