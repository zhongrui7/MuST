module ForceModule
   use KindParamModule, only : IntKind, RealKind, CmplxKind
   use ErrorHandlerModule, only : StopHandler, ErrorHandler, WarningHandler
   use MathParamModule, only : ZERO, Y0inv, SQRTm1
   use IntegerFactorsModule, only : lofk, mofk, m1m
!
public :: initForce,    &
          endForce,     &
          calForce,     &
          getForce,     &
          printForce,   &
          writeForceData, &
          isForceAvailable
!
private
!
   character (len = 50) :: stop_routine
!
   integer (kind=IntKind) :: LocalNumAtoms, GlobalNumAtoms, GroupId
   integer (kind=IntKind) :: print_level
!
   real (kind=RealKind), allocatable, target :: force(:,:)
   real (kind=RealKind), allocatable :: GlobalForce(:,:), AtomicMass(:)
   real (kind=RealKind) :: drift_force(3), drift_accel(3)
!
   logical :: ForceAvailable = .false.
!
contains
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   subroutine initForce(na,istop,iprint)
!  ===================================================================
   use IntegerFactorsModule, only : initIntegerFactors
   use ChemElementModule, only : getAtomicMass
   use SystemModule, only : getLmaxRho
   use SystemModule, only : getNumAtoms, getAtomicNumber
   use SystemModule, only : getNumAlloyElements, getAlloyElementContent
   use GroupCommModule, only : getGroupID
!
   implicit none
!
   character (len=*), intent(in) :: istop
!
   integer (kind=IntKind), intent(in) :: na
   integer (kind=IntKind), intent(in) :: iprint
   integer (kind=IntKind) :: lmax_rho, ig, n, ia
!
   LocalNumAtoms = na
   stop_routine = istop
   print_level = iprint
!
   allocate(force(3,na))
   force = ZERO
!
   lmax_rho=getLmaxRho()
   call initIntegerFactors(lmax_rho)
!
   GlobalNumAtoms = getNumAtoms()
   GroupID = getGroupID('Unit Cell')
   allocate( GlobalForce(3,GlobalNumAtoms))
   allocate( AtomicMass(GlobalNumAtoms))
   GlobalForce = ZERO
!
!  ===================================================================
!  This needs to be fixed for the CPA case.
!  ===================================================================
   do ig = 1, GlobalNumAtoms
      AtomicMass(ig) = ZERO
      do ia = 1, getNumAlloyElements(ig)
         n = getAtomicNumber(ig,ia)
         AtomicMass(ig) = AtomicMass(ig) +                            &
                          getAlloyElementContent(ig,ia)*getAtomicMass(n)
      enddo
   enddo
!  ===================================================================
!
   ForceAvailable = .false.
!
   end subroutine initForce
!  ===================================================================
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   subroutine endForce()
!  ===================================================================
   use IntegerFactorsModule, only : endIntegerFactors
   implicit none
!
!  -------------------------------------------------------------------
   call endIntegerFactors()
!  -------------------------------------------------------------------
   deallocate( force, GlobalForce, AtomicMass )
!
   ForceAvailable = .false.
!
   end subroutine endForce
!  ===================================================================
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   subroutine calForce()
!  ===================================================================
   use AtomModule, only : getLocalAtomicNumber, getPotLmax
   use PublicTypeDefinitionsModule, only : GridStruct
   use RadialGridModule, only : getMaxNumRmesh, getGrid
   use SystemModule, only : setForce
   use Atom2ProcModule, only : getGlobalIndex
   use GroupCommModule, only : GlobalSumInGroup
!
   implicit none
!
   integer (kind=IntKind) :: id, iend, jrc, id_glb, ig
!
   real (kind=RealKind) :: esf(3), csf(3), Zi
   real (kind=RealKind), pointer :: r_mesh(:)
   real (kind=RealKind) :: total_mass
!
   type (GridStruct), pointer :: Grid
!
   iend = getMaxNumRmesh()
   do id = 1, LocalNumAtoms
      if (getPotLmax(id) > 0) then
         Grid => getGrid(id)
         jrc = Grid%jmt       ! Use muffin-tin radius as the bounding sphere
                              ! radius for core states
!jrc = iend  !ywg, 12/03/2014
         iend = Grid%jend
         r_mesh => Grid%r_mesh(:)
         esf = ZERO; csf = ZERO
         Zi = getLocalAtomicNumber(id)
!        -------------------------------------------------------------
         call calElectroStaticField( id, Zi, iend, r_mesh, esf )
         call calForceOnCoreStates( id, jrc, r_mesh, csf )
!        -------------------------------------------------------------
         force(1:3,id) = esf(1:3)+csf(1:3)
#ifdef DebugForce
         if (print_level >= 0) then
            write(6,'(a,i3,1x,f12.8,1x,6d16.8)')"Zi,esf,csf::", id, Zi,esf,csf
         endif
#endif
      else
         force(1:3,id) = ZERO
      endif
      call setForce(getGlobalIndex(id),force(1:3,id))
   enddo
!
   GlobalForce = ZERO
   do id = 1,LocalNumAtoms
      id_glb = getGlobalIndex(id)
      GlobalForce(1:3,id_glb) = force(1:3,id)
   enddo
   call GlobalSumInGroup(GroupID, GlobalForce,3,GlobalNumAtoms)
!
   drift_force = ZERO
   total_mass = ZERO
   do ig=1,GlobalNumAtoms
      drift_force = drift_force+GlobalForce(1:3,ig)
      total_mass = total_mass + AtomicMass(ig)
   enddo
   drift_accel = drift_force/total_mass
!
   ForceAvailable = .true.
!
   end subroutine calForce
!  ===================================================================
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   function getForce(df,local_id,global_id) result(f)
!  ===================================================================
   use ChemElementModule, only : getAtomicMass
   use Atom2ProcModule, only : getGlobalIndex
   use AtomModule, only : getLocalAtomicNumber
!
   implicit none
!
   integer (kind=IntKind), intent(in), optional :: local_id
   integer (kind=IntKind), intent(in), optional :: global_id
   integer (kind=IntKind) :: n, ig
!
   real (kind=RealKind) :: f(3)
   real (kind=RealKind), intent(out) :: df(3)
!
   f = ZERO; df = ZERO
!
   if (present(local_id)) then
      if (local_id < 1 .or. local_id > LocalNumAtoms) then
         call ErrorHandler('getForce','atom index is out of range',local_id)
      endif
      f = force(:,local_id)
      n = getLocalAtomicNumber(local_id)
!     df = drift_accel*getAtomicMass(n)
      ig = getGlobalIndex(local_id)
      df = drift_accel*AtomicMass(ig)
   else if (present(global_id)) then
      if (global_id < 1 .or. global_id > GlobalNumAtoms) then
      endif
      f = GlobalForce(:,global_id)
      df = drift_accel*AtomicMass(global_id)
   else
      call ErrorHandler('getForce','Atom ID is missing from the calling routine')
   endif
!
   end function getForce
!  ===================================================================
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   subroutine calElectroStaticField(id,Zi,iend,r_mesh,esf)
!  ===================================================================
   use MathParamModule, only : ONE, TWO, HALF, THREE, THIRD, PI, PI4, FOUR
   use MathParamModule, only : CZERO, SQRTm1, SQRT_PI, SQRT2, TEN2m6
   use ChargeDensityModule, only : getMultipoleMoment, getRhoLmax,     &
                                   getChargeDensity, getPseudoNumRpts
   use PotentialTypeModule, only : isMuffinTinFullPotential
   use PotentialGenerationModule, only : getPseudoDipoleField
   use InterpolationModule, only : FitInterp
   use IntegrationModule, only : calIntegration
   use MadelungModule, only : getDLMatrix, getDLFactor
   use SystemModule, only : getAtomicNumber, getNumAtoms, getLmaxRho
   use SystemModule, only : getNumAlloyElements, getAlloyElementContent
   use AtomModule, only : getLocalNumSpecies, getLocalSpeciesContent
   use Atom2ProcModule, only : getGlobalIndex
!
   implicit none
   integer (kind=IntKind), intent(in) :: id, iend
   integer (kind=IntKind) :: ia, ic, ir, ig, kl, jl, l, m, mpot, klsum, msum, lsum
   integer (kind=IntKind) :: jr0, GlobalNumAtoms, kmax_rho, lig, ja
   integer (kind=IntKind), pointer :: mm_table_line(:)
!
   real (kind=RealKind), intent(in) :: Zi, r_mesh(iend)
   real (kind=RealKind), intent(out) :: esf(3)
   real (kind=RealKind) :: sqrt_r(0:iend),rhor(0:iend),intrhor(0:iend)
   real (kind=RealKind), pointer :: dlf(:)
   real (kind=RealKind), pointer :: pdf(:)
   real (kind=RealKind) :: f_tilda, f_mm, dummy, a0
!
   complex (kind=CmplxKind), pointer :: rhot(:)
   complex (kind=CmplxKind), pointer :: dlm(:,:)
   complex (kind=CmplxKind), pointer :: qlm(:)
   complex (kind=CmplxKind) :: sumat, sumkl, cfact, qlm_av
!
   GlobalNumAtoms = getNumAtoms()
   dlm => getDLMatrix(id,a0)
   cfact = -SQRTm1
   jr0 = getPseudoNumRpts(id)
   if (isMuffinTinFullPotential()) then
      nullify(pdf)
   else
      pdf => getPseudoDipoleField(id)
   endif
!
   sqrt_r(0) = ZERO
   do ir=1,jr0
      sqrt_r(ir)=sqrt(r_mesh(ir))
   enddo
!
   esf = ZERO
   do ia = 1, getLocalNumSpecies(id)
      do ic = 1, 3
         if (getRhoLmax(id) > 0) then
            if (ic == 1) then
               rhot => getChargeDensity("Tilda",id,ia,3)
               do ir = 1, jr0
                  rhor(ir) = -real(rhot(ir),kind=RealKind)*SQRT2
               enddo
            else if (ic == 2) then
               rhot => getChargeDensity("Tilda",id,ia,3)
               do ir = 1, jr0
                  rhor(ir) = real(cfact*rhot(ir),kind=RealKind)*SQRT2
               enddo
            else
               rhot => getChargeDensity("Tilda",id,ia,2)
               do ir = 1, jr0
                  rhor(ir) = real(rhot(ir),kind=RealKind)
               enddo
            endif
!           ----------------------------------------------------------
            call FitInterp(4,sqrt_r(1:4),rhor(1:4),ZERO,rhor(0),dummy)
            call calIntegration(jr0+1, sqrt_r(0:jr0), rhor(0:jr0),     &
                                intrhor(0:jr0), 1 )
!           ----------------------------------------------------------
            f_tilda = TWO*PI4*THIRD*intrhor(jr0)
         else
            f_tilda = ZERO
         endif
!
         if (ic < 3) then
            dlf => getDLFactor(3)
            mpot = 1
         else
            dlf => getDLFactor(2)
            mpot = 0
         endif
!        =============================================================
!        if ic = 1
!        sumkl = sum_L sum_j [M^{ij}_{{1,1}L} - M^{ij}_{{1,-1}L}] * (Q^j_L - Z_j * sqrt(4pi) * delta_{L0}
!
!        if ic = 2
!        sumkl = sum_L sum_j [M^{ij}_{{1,1}L} + M^{ij}_{{1,-1}L}] * (Q^j_L - Z_j * sqrt(4pi) * delta_{L0}
!
!        if ic = 3
!        sumkl = sum_L sum_j M^{ij}_{{1,0}L} * (Q^j_L - Z_j * sqrt(4pi) * delta_{L0}
!        =============================================================
         sumkl = CZERO
         kmax_rho = (getLmaxRho()+1)**2
         do kl = kmax_rho, 1, -1
            m = mofk(kl)
            l = lofk(kl)
            jl = ((l+1)*(l+2))/2-l+abs(m)
            qlm => getMultipoleMoment(jl,mm_table_line)
            msum = m - mpot
            lsum = l + 1
            klsum = (lsum+1)**2-lsum+msum
            sumat = CZERO
            if (m < 0) then
               do ig = 1, GlobalNumAtoms
                  qlm_av = CZERO
                  do ja = 1, getNumAlloyElements(ig)
                     lig = mm_table_line(ig) + ja
                     qlm_av = qlm_av + qlm(lig)*getAlloyElementContent(ig,ja)
                  enddo
                  sumat = sumat + m1m(m)*dlm(ig,klsum)*conjg(qlm_av)/a0**lsum
               enddo
            else if (l == 0) then
               do ig = 1, GlobalNumAtoms
                  qlm_av = CZERO
                  do ja = 1, getNumAlloyElements(ig)
                     lig = mm_table_line(ig) + ja
                     qlm_av = qlm_av + (qlm(lig)-getAtomicNumber(ig,ja)*Y0inv)*getAlloyElementContent(ig,ja)
                  enddo
                  sumat = sumat + dlm(ig,klsum)*qlm_av/a0
               enddo
            else
               do ig = 1, GlobalNumAtoms
                  qlm_av = CZERO
                  do ja = 1, getNumAlloyElements(ig)
                     lig = mm_table_line(ig) + ja
                     qlm_av = qlm_av + qlm(lig)*getAlloyElementContent(ig,ja)
                  enddo
                  sumat = sumat + dlm(ig,klsum)*qlm_av/a0**lsum
               enddo
            endif
            sumkl = sumkl + dlf(kl)*sumat
         enddo
         if (ic == 1) then
            f_mm = SQRT2*real(sumkl,kind=RealKind)
         else if (ic == 2) then
            f_mm = -SQRT2*real(cfact*sumkl,kind=RealKind)
         else
            f_mm = -real(sumkl,kind=RealKind)
         endif
!
         dummy = sqrt(THREE/PI)
#ifdef DebugForce
         if (abs(pdf(ic) + dummy*(f_tilda+f_mm)) > TEN2m6) then
            if (ic == 1) then
               write(6,'(/,a,i3,a)') 'ig = ',getGlobalIndex(id),'-- along x'
            else if (ic == 2) then
               write(6,'(/,a,i3,a)') 'ig = ',getGlobalIndex(id),'-- along y'
            else
               write(6,'(/,a,i3,a)') 'ig = ',getGlobalIndex(id),'-- along z'
            endif
            write(6,'(a,d16.8)') 'Force from the pseudo charge density = ',Zi*pdf(ic)
            write(6,'(a,d16.8)') 'Force from the onsite tilda density  = ',Zi*dummy*f_tilda
            write(6,'(a,d16.8)') 'Force from the multipole moments     = ',Zi*dummy*f_mm
            write(6,'(a,d16.8)') 'Total force on the nucleus           = ',  &
                                 Zi*pdf(ic) + Zi*dummy*(f_tilda+f_mm)
         endif
#endif
         if (isMuffinTinFullPotential()) then
            esf(ic) = esf(ic) + Zi*dummy*(f_tilda+f_mm)*getLocalSpeciesContent(id,ia)
         else
            esf(ic) = esf(ic) + Zi*(pdf(ic) + dummy*(f_tilda+f_mm))*getLocalSpeciesContent(id,ia)
         endif
      enddo
   enddo
!
   nullify(mm_table_line)
   nullify(rhot, dlm, dlf, qlm, pdf)
!
   end subroutine calElectroStaticField
!  ===================================================================
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   subroutine calForceOnCoreStates(id,jrc,r_mesh,csf)
!  ===================================================================
   use MathParamModule, only : ONE, TWO, THREE, FOUR, THIRD, PI, PI2, SQRTm1
   use ScfDataModule, only : n_spin_pola
   use AtomModule, only : getLocalNumSpecies, getLocalSpeciesContent
   use CoreStatesModule, only : getDeepCoreDensity, getSemiCoreDensity
   use CoreStatesModule, only : getCoreDensityRmeshSize
   use PotentialGenerationModule, only : getOldPotential => getPotential
   use InterpolationModule, only : FitInterp
   use IntegrationModule, only : calIntegration
!
   implicit none
!
   integer (kind=IntKind), intent(in) :: id, jrc
   integer (kind=IntKind) :: ir, ic, is, ia
!
   real (kind=RealKind), intent(in) :: r_mesh(1:jrc)
   real (kind=RealKind), intent(out) :: csf(3)
   real (kind=RealKind) :: vr2(1:jrc),dv(1:jrc)
   real (kind=RealKind) :: sqrt_r(0:jrc),rdv(0:jrc),intrdv(0:jrc)
   real (kind=RealKind), pointer :: deepcore(:), semicore(:)
   real (kind=RealKind) :: dummy
!
   complex (kind=CmplxKind) :: cfact
   complex (kind=CmplxKind), pointer :: pot(:)
!
   if (jrc > getCoreDensityRmeshSize(id)) then
      call ErrorHandler('calForceOnCoreStates','jrc > Core density size', &
                        jrc, getCoreDensityRmeshSize(id))
   endif
!
   sqrt_r(0) = ZERO
   do ir=1,jrc
      sqrt_r(ir)=sqrt(r_mesh(ir))
   enddo
!
   csf(1:3) = ZERO
!
   cfact = -SQRTm1
   do ia = 1, getLocalNumSpecies(id)
      do is = 1, n_spin_pola
         deepcore => getDeepCoreDensity(id,ia,is)
         semicore => getSemiCoreDensity(id,ia,is)
!
         do ic=1,3
            if (ic == 1) then
!               pot => getOldPotential(id,ia,is,3)
               pot => getOldPotential("Total",id,ia,is,3)
               do ir=1,jrc
                  vr2(ir)=-real(pot(ir),kind=RealKind)*r_mesh(ir)*r_mesh(ir)
               enddo
            else if (ic == 2) then
!               pot => getOldPotential(id,ia,is,3)
               pot => getOldPotential("Total",id,ia,is,3)
               do ir=1,jrc
                  vr2(ir)=real(cfact*pot(ir),kind=RealKind)*r_mesh(ir)*r_mesh(ir)
               enddo
            else
!               pot => getOldPotential(id,ia,is,2)
               pot => getOldPotential("Total",id,ia,is,2)
               do ir=1,jrc
                  vr2(ir)=real(pot(ir),kind=RealKind)*r_mesh(ir)*r_mesh(ir)/sqrt(TWO)
               enddo
            endif
!           ---------------------------------------------------------
            call newder(vr2(1:jrc),dv(1:jrc),sqrt_r(1:jrc),jrc)
!           ---------------------------------------------------------
            do ir=1,jrc
               rdv(ir)=(deepcore(ir)+semicore(ir))*dv(ir) ! This needs to be checked/fixed in the 
                                                          ! full-potential semi-core case
            enddo
!           ---------------------------------------------------------
            call FitInterp(4,sqrt_r(1:4),rdv(1:4),ZERO,rdv(0),dummy)
            call calIntegration(0,jrc+1,sqrt_r(0:jrc),rdv(0:jrc),intrdv(0:jrc))
!           ---------------------------------------------------------
            csf(ic) = csf(ic) + intrdv(jrc)*getLocalSpeciesContent(id,ia)
         enddo
      enddo
   enddo
   csf(1:3) = -TWO*sqrt(PI2*THIRD)*csf(1:3)
#ifdef DebugForce
   write(6,'(a,3d16.8)')'csf(1:3) = ',csf(1:3)
#endif
   nullify(deepcore, semicore)
!
   end subroutine calForceOnCoreStates
!  ==================================================================
!
!  ******************************************************************
!
!  cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   subroutine printForce()
!  ==================================================================
   implicit none
!
   integer (kind=IntKind) :: id, ig
!
   real (kind=RealKind) :: f_mag
!
   if (.not.ForceAvailable) then
      call WarningHandler('printForce','The H-F force is not calculated')
      return
   endif
!
   write(6,'(/,80(''-''))')
   write(6,'(/,24x,a)')'**************************'
   write(6,'( 24x,a )')'* Output from printForce *'
   write(6,'(24x,a,/)')'**************************'
   write(6,'(/,80(''=''))')
   write(6,'(a)')'Force Value Table'
   write(6,'(80(''=''))')
   write(6,'(a)')'   Local ID            Fx               Fy               Fz               |F|'
   write(6,'(80(''-''))')
   do id=1,LocalNumAtoms
      f_mag = sqrt(force(1,id)**2+force(2,id)**2+force(3,id)**2)
      write(6,'(2x,i6,4x,4(2x,f15.8))')id,force(1:3,id),f_mag
   enddo
   write(6,'(80(''=''))')
!
   write(6,'(/,80(''-''))')
   write(6,'(/,24x,a)')'**************************'
   write(6,'( 24x,a )')'* Output from printForce *'
   write(6,'(24x,a,/)')'**************************'
   write(6,'(/,80(''=''))')
   write(6,'(a)')'Force Value Table'
   write(6,'(80(''=''))')
   write(6,'(a)')'   Global ID          Fx               Fy               Fz               |F|'
   write(6,'(80(''-''))')
   do ig=1,GlobalNumAtoms
      f_mag = sqrt(GlobalForce(1,ig)**2+GlobalForce(2,ig)**2+GlobalForce(3,ig)**2)
      write(6,'(2x,i6,4x,4(2x,f15.8))')ig,GlobalForce(1:3,ig),f_mag
   enddo
   write(6,'(80(''-''))')
   write(6,'(a,4(f15.8,2x))')"Drift Force:",                         &
      drift_force(1:3),sqrt(drift_force(1)**2+drift_force(2)**2+drift_force(3)**2)
   write(6,'(/,a)')'Applying condition that total force on unit cell = 0, the corrected Forces are'
   write(6,'(80(''=''))')
   write(6,'(a)')'   Global ID          Fx               Fy               Fz               |F|'
   write(6,'(80(''-''))')
   do ig=1,GlobalNumAtoms
      f_mag = sqrt( (GlobalForce(1,ig)-AtomicMass(ig)*drift_accel(1))**2            &
                   +(GlobalForce(2,ig)-AtomicMass(ig)*drift_accel(2))**2            &
                   +(GlobalForce(3,ig)-AtomicMass(ig)*drift_accel(3))**2 )
      write(6,'(2x,i6,4x,4(2x,f15.8))')id,GlobalForce(:,ig)-AtomicMass(ig)*drift_accel,f_mag
   enddo
!
   write(6,'(80(''=''))')
!
   end subroutine printForce
!  ==================================================================
!
!  ******************************************************************
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
!  This subroutine writes the Hellmanm-Feynman force to FORCE_DATA file.
!  Combining FORCE_DATA files allows to generate FORCE_SETS file as an 
!  input for PHONONPY 
!
!  The format of FORCE_SETS file is described as the follows:
!
!  This format is the default format of phonopy and force constants can be
!  calculated by built-in force constants calculator of phonopy by finite
!  difference method, though external force constants calculator can be
!  also used to obtain force constants with this format by the fitting
!  approach.
! 
!  This file gives sets of forces in supercells with finite atomic
!  displacements. Each supercell involves one displaced atom. The first
!  line is the number of atoms (NA) in supercell. The second line gives 
!  number of calculated supercells (NC) with displacements. Below the 
!  lines, sets of forces with displacements are written. 
!
!  In each set, firstly the index of the displaced atom (DA) in supercell 
!  is written. Secondary, the atomic displacement in Cartesian coordinates 
!  (DISP) is written. Below the displacement line, atomic forces (HF_FORCE) 
!  in Cartesian coordinates are successively written, for each atom in 
!  the unit cell. 
!
!  This is repeated for the set of displacements (=NC). 
!
!  Blank likes are simply ignored.
!
!  FORCE_DATA contains the forces for the current supercell
!  ===================================================================
   subroutine writeForceData(fpath)
!  ===================================================================
   use KindParamModule, only : IntKind, RealKind
   use PhysParamModule, only : Bohr2Angstrom, Ryd2eV
   use ErrorHandlerModule, only : ErrorHandler
!
   implicit none
!
   character (len=*), intent(in) :: fpath
!
   integer (kind=IntKind) :: ia, ios, ig
   integer (kind=IntKind), parameter :: funit = 201
!
   real (kind=RealKind) :: AU2SI
!
   if (.not.ForceAvailable) then
      call WarningHandler('writeForceData','The H-F force is not calculated')
      return
   endif
!
   AU2SI = Ryd2eV/Bohr2Angstrom
!
   open(unit=funit,file=trim(fpath)//'FORCE_DATA',form='formatted',   &
        status='unknown',iostat=ios, action='write')
   if (ios > 0) then
      call ErrorHandler('writeForceData','Error to open FORCE_DATA for writing',ios)
   endif
!  ===================================================================
!  hf_force = the Hellmann-Feynman force acting on each atom in the
!             supercell. The written data are in eV/Angstrom units
!  ===================================================================
   do ig = 1, GlobalNumAtoms
      write(funit,'(f15.10,1x,f15.10,1x,f15.10)')(GlobalForce(1:3,ig)  &
                                                  -AtomicMass(ig)*drift_accel(1:3))*AU2SI
   enddo
!
   close(funit)
!
   end subroutine writeForceData
!  ===================================================================
!
!  ******************************************************************
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   function isForceAvailable() result(y)
!  ===================================================================
   implicit none
!
   logical :: y
!
   y = ForceAvailable
!
   end function isForceAvailable
!  ===================================================================
end module ForceModule
