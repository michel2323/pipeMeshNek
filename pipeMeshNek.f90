program pipeMeshNek

!==============================================================================
! geometry definitions
!
! (X) : border number
!
!      ____________________________L_(2)_______________________________
!      |                                                               |
!      |                                                               |
!      R (1)                                                           | (3)
!      |                                                               |
!  __ .| __ . __ . __ . __ . __ . __ . __ . __ . __ . __ . __ . __ . __| . __ 
!    (0,0,0)            axis of symmetry (4)
!
!==============================================================================


!==============================================================================
! variables definition

  IMPLICIT NONE
   ! geometry variables
   REAL(KIND=8)   :: R   ! pipe radius
   REAL(KIND=8)   :: L   ! pipe length
   REAL(KIND=8)   :: lSq ! side of the inner square
   REAL(KIND=8)   :: iR  ! inner element radius
   REAL(KIND=8)   :: oR  ! outer element radius
   ! mesh variables
   INTEGER        :: nR  ! number of elements on the radius (has to be > nTh/8)
   INTEGER        :: nL  ! number of elements along the pipe
   INTEGER        :: nTh ! number of circular sweeps (has to be >= 8 and a power of 2)
   REAL(KIND=8)   :: rR  ! element ratio along the radius
   REAL(KIND=8)   :: rL  ! element ratio along the pipe
   REAL(KIND=8)   :: sR  ! "summation"
   REAL(KIND=8)   :: dR  ! delta element
   REAL(KIND=8)   :: dL  ! delta element
   REAL(KIND=8)   :: de  ! delta element
   REAL(KIND=8)   :: rP0 ! radius "penalization", inner part
   REAL(KIND=8)   :: rP1 ! radius "penalization", outer part
   TYPE element
      INTEGER          :: num
      INTEGER          :: group
      CHARACTER(LEN=1) :: groupL = 'a'
      ! vertices
      REAL(KIND=8), DIMENSION(8) :: x
      REAL(KIND=8), DIMENSION(8) :: y
      REAL(KIND=8), DIMENSION(8) :: z
      ! faces
      LOGICAL,      DIMENSION(8) :: curvedEdge
      REAL(KIND=8), DIMENSION(8) :: curvedEdgeR = 0
      ! boundary conditions
      CHARACTER(LEN=2), DIMENSION(6)   :: bcType
      REAL(KIND=8),     DIMENSION(6,5) :: bcParameters = 0
   END TYPE element
   TYPE(element), DIMENSION(:), ALLOCATABLE  :: elem ! elements constituting the mesh
   INTEGER        :: nEl ! number of elements (total)
   INTEGER        :: nSq ! number of elements on the side of the inner square
   INTEGER        :: nPp ! number of elements in the central tube
   REAL(KIND=8)   :: alpha ! circular sweep angle
   INTEGER        :: nCurvedEdges ! number of curved edges
   INTEGER        :: nFpp  ! number of elements on one face of the            pipe
   INTEGER        :: nFpp4 ! number of elements on a quarter of a face of the pipe
   ! miscellaneous
   LOGICAL        :: debugFlag
   INTEGER        :: i, j, row, col
   INTEGER        :: fid1 = 100, fid2 = 101
   LOGICAL        :: existFlag
   CHARACTER(LEN=24) :: nameRea
   REAL(KIND=8)   :: PI = 4d0*DATAN(1d0)
   REAL(KIND=8)   :: SQ22 = SQRT(2d0)/2d0


!==============================================================================
! read input file 'INPUTgeometry'

   INQUIRE (FILE='INPUTgeometry', EXIST=existFlag)
   IF (.NOT.existFlag) THEN
      WRITE(*,*) '*************************************'
      WRITE(*,*) '*** ERROR:                        ***'
      WRITE(*,*) '*** File not found                ***'
      WRITE(*,*) '*** INPUTgeometry                 ***'
      WRITE(*,*) '*************************************'
      WRITE(*,*) 'STOP.'
      STOP
   ELSE
      OPEN(UNIT=fid1, FILE='INPUTgeometry', STATUS='old', FORM='formatted', ACTION='read')
   ENDIF

   READ(fid1,*) R
   READ(fid1,*) L
   READ(fid1,*) ! jump one line
   READ(fid1,*) nR
   READ(fid1,*) rP0
   READ(fid1,*) rP1
   READ(fid1,*) nL
   READ(fid1,*) nTh
   READ(fid1,*) ! jump one line
   READ(fid1,*) rR
   READ(fid1,*) rL
   READ(fid1,*) ! jump one line
   READ(fid1,*) debugFlag

   CLOSE(fid1)


!==============================================================================
! check the input

   ! check if the number of circular sweeps is >= 8 and a power of 2
   !
   IF ( nTh.LT.8 .OR. MODULO(LOG(nTh*1d0)/LOG(2d0),1d0).GT.0d0 ) THEN
      WRITE(*,*) '******************************************'
      WRITE(*,*) '*** ERROR:                             ***'
      WRITE(*,*) '*** The number of circular sweeps      ***'
      WRITE(*,*) '*** (nTh) has to be >= 8               ***'
      WRITE(*,*) '*** and a power of 2.                  ***'
      WRITE(*,*) '******************************************'
      WRITE(*,*) 'STOP.'
      STOP
   ENDIF

   ! check if nR > nTh/8
   !
   IF ( nR .LE. nTh/8 ) THEN
      WRITE(*,*) '******************************************'
      WRITE(*,*) '*** ERROR:                             ***'
      WRITE(*,*) '*** The number of elements on the      ***'
      WRITE(*,*) '*** radius (nR) has to be >= nTh/8.    ***'
      WRITE(*,*) '******************************************'
      WRITE(*,*) 'STOP.'
      STOP
   ENDIF

!==============================================================================
! do some preliminary computations
   
   ! mesh
   !
   alpha = 2d0*PI/nTH

   nSq = nTh / 8

   nFpp  = 4*nSq**2 + (nR-nSq)*nTh
   nFpp4 = nFpp / 4

   nPp = nFpp * nL

   nEl = nPp

   ! ratios
   !
   sR = 0d0
   DO i = 1, (nR-nSq)
      sR = sR + rR**i
   ENDDO
   dR  = R/(nSq+sR)
   lSq = nSq*dR

   sR = 0d0
   DO i = 1, nL
      sR = sR + rL**(i-1)
   ENDDO
   dL = L/sR


   ALLOCATE( elem(nEl) )

!==============================================================================
! write a little output to screen

   WRITE(*,*)
   WRITE(*,'(a)') '--> Geometry data:'
   WRITE(*,*)
   WRITE(*,'(4x,a4,1x,f7.3)') 'R =', R
   WRITE(*,'(4x,a4,1x,f7.3)') 'L =', L
   WRITE(*,*)
   WRITE(*,'(4x,a4,1x,f7.3,3x,a6,1x,f7.3,1x,a4,1x,f7.3)') 'rR =', rR, '| e0 =', dR, 'e1 =', rR**(nR  -1)*dR
   WRITE(*,'(4x,a4,1x,f7.3,3x,a6,1x,f7.3,1x,a4,1x,f7.3)') 'rL =', rL, '| e0 =', dL, 'e1 =', rL**(nL  -1)*dL
   WRITE(*,*)
   WRITE(*,*)
   WRITE(*,'(a)') '--> Element data:'
   WRITE(*,*)
   WRITE(*,'(4x,a6,1x,i10)') 'nFpp =', nFpp
   WRITE(*,*)
   !WRITE(*,'(4x,a6,1x,i10)') 'nPp  =', nPp
   !WRITE(*,*)
   WRITE(*,'(4x,a6,1x,i10)') 'nEl  =', nEl
   WRITE(*,*)

!==============================================================================
! create the mesh

   i = 0

   ! 1/4 of first face
   !
   ! SQUARE PART
   !
   DO row = 1, nSq
      !
      DO col = 1, nSq
         !
         i = i + 1
         !
         elem(i)%num = i
         elem(i)%group = 1

         elem(i)%curvedEdge(:) = .FALSE.

         elem(i)%bcType(:) = 'E'
         elem(i)%bcType(5) = 'v'

         ! front face
         elem(i)%bcParameters(5,1) = i-nFpp
         elem(i)%bcParameters(5,2) = 6
         ! back face
         elem(i)%bcParameters(6,1) = i+nFpp
         elem(i)%bcParameters(6,2) = 5
         ! right face
         IF ( col .NE. nSq ) THEN
            elem(i)%bcParameters(3,1) = i+1
            elem(i)%bcParameters(3,2) = 1
         ELSE
            elem(i)%bcParameters(3,1) = nSq**2+nSq
            elem(i)%bcParameters(3,2) = 1
         ENDIF
         ! left face
         IF ( col .NE. 1 ) THEN
            elem(i)%bcParameters(1,1) = i-1
            elem(i)%bcParameters(1,2) = 3
         ELSE
            elem(i)%bcParameters(1,1) = nFpp4+1
            elem(i)%bcParameters(1,2) = 4
         ENDIF
         ! bottom face
         IF ( row .NE. 1 ) THEN
            elem(i)%bcParameters(4,1) = i-nSq
            elem(i)%bcParameters(4,2) = 2
         ELSE
            elem(i)%bcParameters(4,1) = 1-nFpp4 + (col-1)*nSq
            elem(i)%bcParameters(4,2) = 1
         ENDIF
         ! top face
         IF ( row .NE. nSq ) THEN
            elem(i)%bcParameters(2,1) = i+nSq
            elem(i)%bcParameters(2,2) = 4
         ELSE
            elem(i)%bcParameters(2,1) = nSq**2+2*nSq-col+1
            elem(i)%bcParameters(2,2) = 1
         ENDIF

         IF ( col > row ) THEN
            ! lower right part

            iR = lSq/nSq * (col-1) * (rP0 + (rP1-rP0)/nSq*(col-1))
            oR = lSq/nSq *  col    * (rP0 + (rP1-rP0)/nSq* col   )

!            elem(i)%curvedEdge(1) = .TRUE.
!            elem(i)%curvedEdge(3) = .TRUE.
!            elem(i)%curvedEdge(5) = .TRUE.
!            elem(i)%curvedEdge(7) = .TRUE.
!            elem(i)%curvedEdgeR(1) = -iR
!            elem(i)%curvedEdgeR(3) = oR
!            elem(i)%curvedEdgeR(5) = -iR
!            elem(i)%curvedEdgeR(7) = oR

            elem(i)%y(1) = elem(i-1)%y(4)
            elem(i)%y(2) = elem(i-1)%y(3)
!            elem(i)%y(3) = oR * DCOS( DASIN((elem(i-1)%x(3)+(oR-lSq/nSq*col)*SQ22)/oR) ) &
!                           - (oR - lSq/nSq*col)*SQ22 * 1.5*(nSq-col+2)
!            elem(i)%y(4) = oR * DCOS( DASIN((elem(i-1)%x(4)+(oR-lSq/nSq*col)*SQ22)/oR) ) &
!                           - (oR - lSq/nSq*col)*SQ22 * 1.5*(nSq-col+2)
            elem(i)%y(3) = oR * DCOS( DASIN(elem(i-1)%x(3)/oR) ) &
                           - (oR - lSq/nSq*col)*SQ22
            elem(i)%y(4) = oR * DCOS( DASIN(elem(i-1)%x(4)/oR) ) &
                           - (oR - lSq/nSq*col)*SQ22

            elem(i)%x(1) = elem(i-1)%x(4)
            elem(i)%x(2) = elem(i-1)%x(3)
            elem(i)%x(3) = elem(i)%x(2)
            elem(i)%x(4) = elem(i)%x(1)

            if ( debugFlag ) then
               write(*,*) 'lr ', row, col, rP0+(rP1-rP0)/nSq*col
            endif

         ELSEIF ( row > col ) THEN
            ! upper left part

            iR = lSq/nSq * (row-1) * (rP0 + (rP1-rP0)/nSq*(row-1))
            oR = lSq/nSq *  row    * (rP0 + (rP1-rP0)/nSq* row   )

!            elem(i)%curvedEdge(2) = .TRUE.
!            elem(i)%curvedEdge(4) = .TRUE.
!            elem(i)%curvedEdge(6) = .TRUE.
!            elem(i)%curvedEdge(8) = .TRUE.
!            elem(i)%curvedEdgeR(2) = oR
!            elem(i)%curvedEdgeR(4) = -iR
!            elem(i)%curvedEdgeR(6) = oR
!            elem(i)%curvedEdgeR(8) = -iR

            elem(i)%y(1) = elem(i-nSq)%y(2)
            elem(i)%y(2) = elem(i)%y(1)
            elem(i)%y(3) = elem(i-nSq)%y(3)
            elem(i)%y(4) = elem(i)%y(3)

            elem(i)%x(1) = elem(i-nSq)%x(2)
!            elem(i)%x(2) = oR * DSIN( DACOS((elem(i)%y(2)+(oR-lSq/nSq*row)*SQ22)/oR) ) &
!                           - (oR - lSq/nSq*row)*SQ22 * 1.5*(nSq-row+2)
!            elem(i)%x(3) = oR * DSIN( DACOS((elem(i)%y(4)+(oR-lSq/nSq*row)*SQ22)/oR) ) &
!                           - (oR - lSq/nSq*row)*SQ22 * 1.5*(nSq-row+2)
            elem(i)%x(2) = oR * DSIN( DACOS(elem(i)%y(2)/oR) ) &
                           - (oR - lSq/nSq*row)*SQ22
            elem(i)%x(3) = oR * DSIN( DACOS(elem(i)%y(4)/oR) ) &
                           - (oR - lSq/nSq*row)*SQ22
            elem(i)%x(4) = elem(i-nSq)%x(3)

            if ( debugFlag ) then
               write(*,*) 'ul ', row, col, rP0+(rP1-rP0)/nSq*row
            endif

         ELSE
            ! diagonal

            oR = lSq/nSq * row * (rP0 + (rP1-rP0)/nSq*row)

!            elem(i)%curvedEdge(2) = .TRUE.
!            elem(i)%curvedEdge(3) = .TRUE.
!            elem(i)%curvedEdge(6) = .TRUE.
!            elem(i)%curvedEdge(7) = .TRUE.
!            elem(i)%curvedEdgeR(2) = oR
!            elem(i)%curvedEdgeR(3) = oR
!            elem(i)%curvedEdgeR(6) = oR
!            elem(i)%curvedEdgeR(7) = oR

            elem(i)%y(1) = lSq/nSq * (row-1) * SQ22
            elem(i)%y(2) = elem(i)%y(1)
            elem(i)%y(3) = lSq/nSq * row     * SQ22
!            elem(i)%y(4) = oR * DCOS( DASIN((lSq/nSq*(row-1)*SQ22+(oR-lSq/nSq*col)*SQ22)/oR) ) &
!                           - (oR - lSq/nSq*row)*SQ22 * 1.5*(nSq-row+2)
            elem(i)%y(4) = oR * DCOS( DASIN(lSq/nSq*(row-1)*SQ22/oR) ) &
                           - (oR - lSq/nSq*row)*SQ22

            elem(i)%x(1) = lSq/nSq * (row-1) * SQ22
!            elem(i)%x(2) = oR * DSIN( DACOS((elem(i)%y(2)+(oR-lSq/nSq*col)*SQ22)/oR) ) &
!                           - (oR - lSq/nSq*row)*SQ22 * 1.5*(nSq-row+2)
            elem(i)%x(2) = oR * DSIN( DACOS(elem(i)%y(2)/oR) ) &
                           - (oR - lSq/nSq*row)*SQ22
            elem(i)%x(3) = lSq/nSq * row     * SQ22
            elem(i)%x(4) = elem(i)%x(1)

            if ( debugFlag ) then
               write(*,*) 'd  ', row, oR
            endif

         ENDIF

         elem(i)%y(5) = elem(i)%y(1)
         elem(i)%y(6) = elem(i)%y(2)
         elem(i)%y(7) = elem(i)%y(3)
         elem(i)%y(8) = elem(i)%y(4)

         elem(i)%x(5) = elem(i)%x(1)
         elem(i)%x(6) = elem(i)%x(2)
         elem(i)%x(7) = elem(i)%x(3)
         elem(i)%x(8) = elem(i)%x(4)

         elem(i)%z(1) = 0d0
         elem(i)%z(2) = 0d0
         elem(i)%z(3) = 0d0
         elem(i)%z(4) = 0d0
         elem(i)%z(5) = 0d0 + dL
         elem(i)%z(6) = 0d0 + dL
         elem(i)%z(7) = 0d0 + dL
         elem(i)%z(8) = 0d0 + dL

      ENDDO

   ENDDO
   !
   ! CIRCULAR PART
   !
   iR  = lSq*rP1
   oR  = lSq + dR*rR
   col = 1
   DO row = 1, nTh/8
      !
      i = i + 1
      !
      elem(i)%num = i
      elem(i)%group = 1

      elem(i)%curvedEdge(:) = .FALSE.
!      elem(i)%curvedEdge(1) = .TRUE.
      elem(i)%curvedEdge(3) = .TRUE.
!      elem(i)%curvedEdge(5) = .TRUE.
      elem(i)%curvedEdge(7) = .TRUE.
!      elem(i)%curvedEdgeR(1) = -iR
      elem(i)%curvedEdgeR(3) = oR
!      elem(i)%curvedEdgeR(5) = -iR
      elem(i)%curvedEdgeR(7) = oR

      elem(i)%bcType(:) = 'E'
      elem(i)%bcType(5) = 'v'

      ! front face
      elem(i)%bcParameters(5,1) = i-nFpp
      elem(i)%bcParameters(5,2) = 6
      ! back face
      elem(i)%bcParameters(6,1) = i+nFpp
      elem(i)%bcParameters(6,2) = 5
      ! right face
      elem(i)%bcParameters(3,1) = i+nTh/4
      elem(i)%bcParameters(3,2) = 1
      ! left face
      elem(i)%bcParameters(1,1) = row*nSq
      elem(i)%bcParameters(1,2) = 3
      ! bottom face
      IF ( row .NE. 1 ) THEN
         elem(i)%bcParameters(4,1) = i-1
         elem(i)%bcParameters(4,2) = 2
      ELSE
         elem(i)%bcParameters(4,1) = 1-nFpp4+nSq**2+nTh/8
         elem(i)%bcParameters(4,2) = 2
      ENDIF
      ! top face
      elem(i)%bcParameters(2,1) = i+1
      elem(i)%bcParameters(2,2) = 4

      elem(i)%y(1) = elem(nSq*row)%y(4)
      elem(i)%y(2) = elem(nSq*row)%y(3)
      elem(i)%y(3) = oR * COS(alpha*row)
      elem(i)%y(4) = oR * COS(alpha*(row-1))
      elem(i)%y(5) = elem(i)%y(1)
      elem(i)%y(6) = elem(i)%y(2)
      elem(i)%y(7) = elem(i)%y(3)
      elem(i)%y(8) = elem(i)%y(4)

      elem(i)%x(1) = elem(nSq*row)%x(4)
      elem(i)%x(2) = elem(nSq*row)%x(3)
      elem(i)%x(3) = oR * SIN(alpha*row)
      elem(i)%x(4) = oR * SIN(alpha*(row-1))
      elem(i)%x(5) = elem(i)%x(1)
      elem(i)%x(6) = elem(i)%x(2)
      elem(i)%x(7) = elem(i)%x(3)
      elem(i)%x(8) = elem(i)%x(4)

      elem(i)%z(1) = 0d0
      elem(i)%z(2) = 0d0
      elem(i)%z(3) = 0d0
      elem(i)%z(4) = 0d0
      elem(i)%z(5) = 0d0 + dL
      elem(i)%z(6) = 0d0 + dL
      elem(i)%z(7) = 0d0 + dL
      elem(i)%z(8) = 0d0 + dL

   ENDDO
   row = 1
   DO col = 1, nTh/8
      !
      i = i + 1
      !
      elem(i)%num = i
      elem(i)%group = 1

      elem(i)%curvedEdge(:) = .FALSE.
!      elem(i)%curvedEdge(1) = .TRUE.
      elem(i)%curvedEdge(3) = .TRUE.
!      elem(i)%curvedEdge(5) = .TRUE.
      elem(i)%curvedEdge(7) = .TRUE.
!      elem(i)%curvedEdgeR(1) = -iR
      elem(i)%curvedEdgeR(3) = oR
!      elem(i)%curvedEdgeR(5) = -iR
      elem(i)%curvedEdgeR(7) = oR

      elem(i)%bcType(:) = 'E'
      elem(i)%bcType(5) = 'v'

      ! front face
      elem(i)%bcParameters(5,1) = i-nFpp
      elem(i)%bcParameters(5,2) = 6
      ! back face
      elem(i)%bcParameters(6,1) = i+nFpp
      elem(i)%bcParameters(6,2) = 5
      ! right face
      elem(i)%bcParameters(3,1) = i+nTh/4
      elem(i)%bcParameters(3,2) = 1
      ! left face
      elem(i)%bcParameters(1,1) = nSq**2-col+1
      elem(i)%bcParameters(1,2) = 2
      ! bottom face
      elem(i)%bcParameters(4,1) = i-1
      elem(i)%bcParameters(4,2) = 2
      ! top face
      IF ( col .NE. nSq ) THEN
         elem(i)%bcParameters(2,1) = i+1
         elem(i)%bcParameters(2,2) = 4
      ELSE
         elem(i)%bcParameters(2,1) = nFpp4+nSq**2+1
         elem(i)%bcParameters(2,2) = 4
      ENDIF

      elem(i)%y(1) = elem(nSq**2+1-col)%y(3)
      elem(i)%y(2) = elem(nSq**2+1-col)%y(2)
      elem(i)%y(3) = oR * COS(PI/4+alpha*col)
      elem(i)%y(4) = oR * COS(PI/4+alpha*(col-1))
      elem(i)%y(5) = elem(i)%y(1)
      elem(i)%y(6) = elem(i)%y(2)
      elem(i)%y(7) = elem(i)%y(3)
      elem(i)%y(8) = elem(i)%y(4)

      elem(i)%x(1) = elem(nSq**2+1-col)%x(3)
      elem(i)%x(2) = elem(nSq**2+1-col)%x(2)
      elem(i)%x(3) = oR * SIN(PI/4+alpha*col)
      elem(i)%x(4) = oR * SIN(PI/4+alpha*(col-1))
      elem(i)%x(5) = elem(i)%x(1)
      elem(i)%x(6) = elem(i)%x(2)
      elem(i)%x(7) = elem(i)%x(3)
      elem(i)%x(8) = elem(i)%x(4)

      elem(i)%z(1) = 0d0
      elem(i)%z(2) = 0d0
      elem(i)%z(3) = 0d0
      elem(i)%z(4) = 0d0
      elem(i)%z(5) = 0d0 + dL
      elem(i)%z(6) = 0d0 + dL
      elem(i)%z(7) = 0d0 + dL
      elem(i)%z(8) = 0d0 + dL

   ENDDO
   !
   ! other columns of the circular part
   !
   de = dR*rR**2
   DO row = 1, (nR-nSq-1)

      !iR  = lSq +      dR
      !oR  = lSq + de + dR
      iR  = oR
      oR  = iR + de

      !dR  = de + dR
      de  = rR*de

      DO col = 1, nTh/4
         !
         i = i + 1
         !
         elem(i)%num = i
         elem(i)%group = 1
      
         elem(i)%curvedEdge(:) = .FALSE.
         elem(i)%curvedEdge(3) = .TRUE.
         elem(i)%curvedEdge(7) = .TRUE.
         elem(i)%curvedEdge(1) = .TRUE.
         elem(i)%curvedEdge(5) = .TRUE.
         elem(i)%curvedEdgeR(3) = oR
         elem(i)%curvedEdgeR(7) = oR
         elem(i)%curvedEdgeR(1) = -iR
         elem(i)%curvedEdgeR(5) = -iR
      
         elem(i)%bcType(:) = 'E'
         elem(i)%bcType(5) = 'v'

         ! front face
         elem(i)%bcParameters(5,1) = i-nFpp
         elem(i)%bcParameters(5,2) = 6
         ! back face
         elem(i)%bcParameters(6,1) = i+nFpp
         elem(i)%bcParameters(6,2) = 5
         ! right face
         elem(i)%bcParameters(3,1) = i+nTh/4
         elem(i)%bcParameters(3,2) = 1
         ! left face
         elem(i)%bcParameters(1,1) = i-nTh/4
         elem(i)%bcParameters(1,2) = 3
         ! bottom face
         IF ( col .NE. 1 ) THEN
            elem(i)%bcParameters(4,1) = i-1
            elem(i)%bcParameters(4,2) = 2
         ELSE
            elem(i)%bcParameters(4,1) = -nFpp4+nSq**2+nTh/4*row
            elem(i)%bcParameters(4,2) = 2
         ENDIF
         ! top face
         IF ( col .NE. nTh/4 ) THEN
            elem(i)%bcParameters(2,1) = i+1
            elem(i)%bcParameters(2,2) = 4
         ELSE
            elem(i)%bcParameters(2,1) = nFpp4+nSq**2+nTh/4*row+1
            elem(i)%bcParameters(2,2) = 4
         ENDIF
      
         elem(i)%y(1) = elem(i-nTh/4)%y(4)
         elem(i)%y(2) = elem(i-nTh/4)%y(3)
         elem(i)%y(3) = oR * COS(alpha*col)
         elem(i)%y(4) = oR * COS(alpha*(col-1))
         elem(i)%y(5) = elem(i)%y(1)
         elem(i)%y(6) = elem(i)%y(2)
         elem(i)%y(7) = elem(i)%y(3)
         elem(i)%y(8) = elem(i)%y(4)
      
         elem(i)%x(1) = elem(i-nTh/4)%x(4)
         elem(i)%x(2) = elem(i-nTh/4)%x(3)
         elem(i)%x(3) = oR * SIN(alpha*col)
         elem(i)%x(4) = oR * SIN(alpha*(col-1))
         elem(i)%x(5) = elem(i)%x(1)
         elem(i)%x(6) = elem(i)%x(2)
         elem(i)%x(7) = elem(i)%x(3)
         elem(i)%x(8) = elem(i)%x(4)
      
         elem(i)%z(1) = 0d0
         elem(i)%z(2) = 0d0
         elem(i)%z(3) = 0d0
         elem(i)%z(4) = 0d0
         elem(i)%z(5) = 0d0 + dL
         elem(i)%z(6) = 0d0 + dL
         elem(i)%z(7) = 0d0 + dL
         elem(i)%z(8) = 0d0 + dL
      
      ENDDO

   ENDDO
   !
   ! add "Wall" boundary condition on the external elements
   !
   DO j = nFpp4-nTh/4+1, nFpp4

      elem(j)%bcType(3) = 'W'

   ENDDO
   !
   ! "mirror" the first 1/4 face on the other quarters
   !
   DO i = i+1, 2*nFpp4


      elem(i)%num = i
      elem(i)%group = 1

      elem(i)%curvedEdge(:)  = elem(i-nFpp4)%curvedEdge(:)
      elem(i)%curvedEdgeR(:) = elem(i-nFpp4)%curvedEdgeR(:)

      elem(i)%bcType(:) = elem(i-nFpp4)%bcType(:)
      elem(i)%bcParameters(:,1) = elem(i-nFpp4)%bcParameters(:,1)+nFpp4
      elem(i)%bcParameters(:,2) = elem(i-nFpp4)%bcParameters(:,2)

      elem(i)%y(:) = - elem(i-nFpp4)%x(:)
      elem(i)%x(:) =   elem(i-nFpp4)%y(:)
      elem(i)%z(:) =   elem(i-nFpp4)%z(:)

   ENDDO
   DO i = i, 3*nFpp4

      elem(i)%num = i
      elem(i)%group = 1

      elem(i)%curvedEdge(:)  = elem(i-2*nFpp4)%curvedEdge(:)
      elem(i)%curvedEdgeR(:) = elem(i-2*nFpp4)%curvedEdgeR(:)

      elem(i)%bcType(:) = elem(i-2*nFpp4)%bcType(:)
      elem(i)%bcParameters(:,1) = elem(i-2*nFpp4)%bcParameters(:,1)+2*nFpp4
      elem(i)%bcParameters(:,2) = elem(i-2*nFpp4)%bcParameters(:,2)

      elem(i)%y(:) = - elem(i-2*nFpp4)%y(:)
      elem(i)%x(:) = - elem(i-2*nFpp4)%x(:)
      elem(i)%z(:) =   elem(i-2*nFpp4)%z(:)

   ENDDO
   DO i = i, 4*nFpp4

      elem(i)%num = i
      elem(i)%group = 1

      elem(i)%curvedEdge(:)  = elem(i-3*nFpp4)%curvedEdge(:)
      elem(i)%curvedEdgeR(:) = elem(i-3*nFpp4)%curvedEdgeR(:)

      elem(i)%bcType(:) = elem(i-3*nFpp4)%bcType(:)
      elem(i)%bcParameters(:,1) = elem(i-3*nFpp4)%bcParameters(:,1)+3*nFpp4
      elem(i)%bcParameters(:,2) = elem(i-3*nFpp4)%bcParameters(:,2)

      elem(i)%y(:) =   elem(i-3*nFpp4)%x(:)
      elem(i)%x(:) = - elem(i-3*nFpp4)%y(:)
      elem(i)%z(:) =   elem(i-3*nFpp4)%z(:)

   ENDDO
   i = i - 1
   !
   ! correct boundary conditions at "glue side"
   !
   DO j = 1, nSq
      elem(j)%bcParameters(4,1) = 3*nFpp4+(j-1)*nSq+1
      elem(3*nFpp4+(j-1)*nSq+1)%bcParameters(1,1) = j
   ENDDO
   DO j = 1, (nR-nSq)
      elem(nSq**2+1+(j-1)*nTh/4)%bcParameters(4,1) = 3*nFpp4+nSq**2+nTh/4*j
      elem(3*nFpp4+nSq**2+nTh/4*j)%bcParameters(2,1) = nSq**2+1+(j-1)*nTh/4
   ENDDO
   !
	! advance the face to the end of the pipe
   !
   de = rL * dL
   DO j = 1, nL-1

      CALL advanceFace (1 + nFpp*(j-1), nFpp*j, de, elem)

      de = rL * de

      i = i + nFpp

      IF ( j .EQ. 1 ) THEN

         elem(1+nFpp:nFpp*2)%bcType(5) = 'E'

      ENDIF

   ENDDO
   !
   ! add PERIODIC boundary conditions on first and last face
   !
   DO j = i-nFpp+1, i

      ! write last face
      elem(j)%bcType(6) = 'P'
      elem(j)%bcParameters(6,1) = j-nPp+nFpp
      ! and correct periodicity on the first face
      elem(j-nPp+nFpp)%bcType(5) = 'P'
      elem(j-nPp+nFpp)%bcParameters(5,1) = j

   ENDDO


!==============================================================================
! clean up

   ! eliminate useless parameters in boundary conditions
   !
   ! now we also have periodic elements
   !!!DO i = 1, nEl
   !!!   DO j = 1, 6
   !!!      IF ( elem(i)%bcType(j) .NE. 'E' ) THEN
   !!!         elem(i)%bcParameters(j,:) = 0
   !!!      ENDIF
   !!!   ENDDO
   !!!ENDDO

   ! count curved edges
   !
   nCurvedEdges = 0
   DO i = 1, nEl
      DO j = 1, 8
         IF ( elem(i)%curvedEdge(j) )  nCurvedEdges = nCurvedEdges + 1
      ENDDO
   ENDDO

   ! set to zero any "approximate" zero
   !
   DO i = 1, nEl
      DO j = 1, 8
         IF ( abs(elem(i)%x(j)) .LE. 1d-15 ) THEN
            elem(i)%x(j) = 0d0
         ENDIF
         IF ( abs(elem(i)%y(j)) .LE. 1d-15 ) THEN
            elem(i)%y(j) = 0d0
         ENDIF
         IF ( abs(elem(i)%z(j)) .LE. 1d-15 ) THEN
            elem(i)%z(j) = 0d0
         ENDIF
      ENDDO
   ENDDO


!==============================================================================
! initialize nameRea

   WRITE(nameRea,'(a)') 'base.rea'

   INQUIRE (FILE=trim(nameRea), EXIST=existFlag)
   IF (existFlag) THEN
      WRITE(*,*) '*************************************'
      WRITE(*,*) '*** ERROR:                        ***'
      WRITE(*,*) '*** File already present          ***'
      WRITE(*,*) '*** ', trim(nameRea), '                      ***'
      WRITE(*,*) '*************************************'
      WRITE(*,*) 'STOP.'
      STOP
   ELSE
      OPEN(UNIT=fid2, FILE=trim(nameRea), STATUS='new', ACTION='write')
      CALL initializeMeshFile(fid2, debugFlag)
   ENDIF

!==============================================================================
! write element data

   WRITE(fid2, '(a)') '  ***** MESH DATA *****  6 lines are X,Y,Z;X,Y,Z. Columns corners 1-4;5-8'
   WRITE(fid2, *)     nEl, ' 3 ', nEl, ' NEL,NDIM,NELV'

   DO i = 1, nEl

      CALL writeElement ( fid2, elem(i) )

   ENDDO

!==============================================================================
! write curved side data

   WRITE(fid2, '(1x,a28)') '***** CURVED SIDE DATA *****'
   WRITE(fid2, '(2x,i10,1x,a52)') nCurvedEdges, 'Curved sides follow IEDGE,IEL,CURVE(I),I=1,5, CCURVE'

   DO i = 1, nEl

      CALL writeCurvedEdges ( fid2, elem(i) )

   ENDDO

!==============================================================================
! write boundary conditions

   WRITE(fid2, '(a)') '  ***** BOUNDARY CONDITIONS *****'
   WRITE(fid2, '(a)') '  ***** FLUID BOUNDARY CONDITIONS *****'

   DO i = 1, nEl

      CALL writeBoundaryConditions ( fid2, elem(i) )

   ENDDO

!==============================================================================
! finalize nameRea

   CALL finalizeMeshFile(fid2)
   CLOSE(fid2)

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
! debug: plot with Matlab

   IF ( debugFlag ) THEN
      OPEN(UNIT=fid2, FILE='plotElements', ACTION='write')
      DO i = 1, nEl
         DO j = 1, 8
            WRITE(fid2, *) elem(i)%x(j), elem(i)%y(j), elem(i)%z(j)
         ENDDO
      ENDDO
      CLOSE(fid2)
   ENDIF

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

!==============================================================================
! end of program

   DEALLOCATE(elem)

   WRITE(*,*) 'ALL DONE.'


!==============================================================================
contains

!------------------------------------------------------------------------------

   subroutine advanceFace (firstElem, lastElem, dZ, elem)

      IMPLICIT NONE
      ! input variables
      INTEGER,      INTENT(IN) :: firstElem
      INTEGER,      INTENT(IN) :: lastElem
      REAL(KIND=8), INTENT(IN) :: dZ
      ! input/output variable
      TYPE(element), DIMENSION(:) :: elem
      ! local variables
      INTEGER :: j
      INTEGER :: faceElements


      faceElements = lastElem - firstElem + 1

      DO j = lastElem+1, lastElem+faceElements

         elem(j)%num = j
         elem(j)%group = elem(j-faceElements)%group
         
         elem(j)%curvedEdge(:)  = elem(j-faceElements)%curvedEdge(:)
         elem(j)%curvedEdgeR(:) = elem(j-faceElements)%curvedEdgeR(:)
         
         elem(j)%bcType(:) = elem(j-faceElements)%bcType(:)
         elem(j)%bcParameters(:,1) = elem(j-faceElements)%bcParameters(:,1) + faceElements
         elem(j)%bcParameters(:,2) = elem(j-faceElements)%bcParameters(:,2)
         
         elem(j)%x(:) = elem(j-faceElements)%x(:)
         elem(j)%y(:) = elem(j-faceElements)%y(:)

         elem(j)%z(1:4) = elem(j-faceElements)%z(5:8)
         elem(j)%z(5:8) = elem(j-faceElements)%z(5:8) + dZ

      ENDDO

   end subroutine advanceFace

!------------------------------------------------------------------------------

   subroutine initializeMeshFile (fid, debugFlag)
   
      IMPLICIT NONE
      ! input variables
      INTEGER, INTENT(IN) :: fid
      LOGICAL, INTENT(IN) :: debugFlag

      WRITE(fid, '(a)') ' ****** PARAMETERS *****'
      WRITE(fid, '(a)') '   2.6000      NEKTON VERSION'
      WRITE(fid, '(a)') '   3 DIMENSIONAL RUN'
      WRITE(fid, '(a)') '         118  PARAMETERS FOLLOW'
      WRITE(fid, '(a)') '   1.00000     P001: DENSITY'
      if ( debugFlag ) then
         WRITE(fid, '(a)') '  -100.        P002: VISCOS'
      else
         WRITE(fid, '(a)') '  -3000.       P002: VISCOS'
      endif
      WRITE(fid, '(a)') '   0.00000     P003: : : BETAG'
      WRITE(fid, '(a)') '   0.00000     P004: : : GTHETA'
      WRITE(fid, '(a)') '   0.00000     P005: : : PGRADX'
      WRITE(fid, '(a)') '   0.00000     P006:'
      WRITE(fid, '(a)') '   1.00000     P007: RHOCP'
      WRITE(fid, '(a)') '   1.00000     P008: CONDUCT'
      WRITE(fid, '(a)') '   0.00000     P009:'
      WRITE(fid, '(a)') '   0.00000     P010: FINTIME'
      if ( debugFlag ) then
         WRITE(fid, '(a)') '   8           P011: NSTEPS'
      else
         WRITE(fid, '(a)') '   40003       P011: NSTEPS'
      endif
      WRITE(fid, '(a)') '   5.0E-03     P012: DT'
      WRITE(fid, '(a)') '   0.00000     P013: IOCOMM'
      WRITE(fid, '(a)') '   0.00000     P014: IOTIME'
      if ( debugFlag ) then
         WRITE(fid, '(a)') '   1           P015: IOSTEP'
      else
         WRITE(fid, '(a)') '   200         P015: IOSTEP'
      endif
      WRITE(fid, '(a)') '   0.00000     P016: PSSOLVER: 0=default'
      WRITE(fid, '(a)') '   1.00000     P017:'
      WRITE(fid, '(a)') '  0.500000E-01 P018: GRID < 0 --> # cells on screen'
      WRITE(fid, '(a)') '  -1.00000     P019: INTYPE'
      WRITE(fid, '(a)') '   10.0000     P020: NORDER'
      WRITE(fid, '(a)') '  0.100000E-08 P021: DIVERGENCE'
      WRITE(fid, '(a)') '  0.100000E-08 P022: HELMHOLTZ'
      WRITE(fid, '(a)') '   0.00000     P023: NPSCAL'
      WRITE(fid, '(a)') '  0.100000E-01 P024: TOLREL'
      WRITE(fid, '(a)') '  0.100000E-01 P025: TOLABS'
      WRITE(fid, '(a)') '   1.00000     P026: COURANT/NTAU'
      WRITE(fid, '(a)') '   3.00000     P027: TORDER'
      WRITE(fid, '(a)') '   0.00000     P028: TORDER: mesh velocity (0: p28=p27)'
      WRITE(fid, '(a)') '   0.00000     P029: = magnetic visc if > 0, = -1/Rm if < 0'
      WRITE(fid, '(a)') '   0.00000     P030: > 0 ==> properties set in uservp()'
      WRITE(fid, '(a)') '   0.00000     P031: NPERT: #perturbation modes'
      WRITE(fid, '(a)') '   0.00000     P032: #BCs in re2 file, if > 0'
      WRITE(fid, '(a)') '   0.00000     P033: : :'
      WRITE(fid, '(a)') '   0.00000     P034: : :'
      WRITE(fid, '(a)') '   0.00000     P035: : :'
      WRITE(fid, '(a)') '   0.00000     P036: : : XMAGNET'
      WRITE(fid, '(a)') '   0.00000     P037: : : NGRIDS'
      WRITE(fid, '(a)') '   0.00000     P038: : : NORDER2'
      WRITE(fid, '(a)') '   0.00000     P039: : : NORDER3'
      WRITE(fid, '(a)') '   0.00000     P040:'
      WRITE(fid, '(a)') '   0.00000     P041: 1-->multiplicative SEMG'
      WRITE(fid, '(a)') '   0.00000     P042: 0=gmres/1=pcg'
      WRITE(fid, '(a)') '   0.00000     P043: 0=semg/1=schwarz'
      WRITE(fid, '(a)') '   0.00000     P044: 0=E-based/1=A-based prec.'
      WRITE(fid, '(a)') '   0.00000     P045: Relaxation factor for DTFS'
      WRITE(fid, '(a)') '   0.00000     P046: reserved'
      WRITE(fid, '(a)') '   0.00000     P047: vnu: mesh matieral prop.'
      WRITE(fid, '(a)') '   0.00000     P048: : :'
      WRITE(fid, '(a)') '   0.00000     P049: : :'
      WRITE(fid, '(a)') '   0.00000     P050: : :'
      WRITE(fid, '(a)') '   0.00000     P051:'
      WRITE(fid, '(a)') '   0.00000     P052: IOHIS'
      WRITE(fid, '(a)') '   0.00000     P053:'
      WRITE(fid, '(a)') '   0.00000     P054: fixed flow rate dir: |p54|=1,2,3=x,y,z'
      WRITE(fid, '(a)') '   0.00000     P055: vol.flow rate (p54>0) or Ubar (p54<0)'
      WRITE(fid, '(a)') '   1.00000     P056: : :'
      WRITE(fid, '(a)') '   0.00000     P057: : :'
      WRITE(fid, '(a)') '   0.00000     P058:'
      WRITE(fid, '(a)') '   0.00000     P059: !=0 --> full Jac. eval. for each el.'
      WRITE(fid, '(a)') '   0.00000     P060: !=0 --> init. velocity to small nonzero'
      WRITE(fid, '(a)') '   0.00000     P061:'
      WRITE(fid, '(a)') '   0.00000     P062: >0 --> force byte_swap for output'
      WRITE(fid, '(a)') '   0.00000     P063: =8 --> force 8-byte output'
      WRITE(fid, '(a)') '   0.00000     P064: =1 --> perturbation restart'
      WRITE(fid, '(a)') '   1.00000     P065: #iofiles (eg, 0 or 64); <0 --> sep. dirs'
      WRITE(fid, '(a)') '   6.00000     P066: output : <0=ascii, else binary'
      WRITE(fid, '(a)') '   6.00000     P067: restart: <0=ascii, else binary'
      WRITE(fid, '(a)') '   20000       P068: iastep: freq for avg_all (0=iostep)'
      WRITE(fid, '(a)') '   50000.0     P069: : :     frequency of srf dump'
      WRITE(fid, '(a)') '   0.00000     P070: : :'
      WRITE(fid, '(a)') '   0.00000     P071: : :'
      WRITE(fid, '(a)') '   0.00000     P072: : :'
      WRITE(fid, '(a)') '   0.00000     P073:'
      WRITE(fid, '(a)') '   0.00000     P074: verbose Helmholtz'
      WRITE(fid, '(a)') '   0.00000     P075: : :'
      WRITE(fid, '(a)') '   0.00000     P076: : :'
      WRITE(fid, '(a)') '   0.00000     P077: : :'
      WRITE(fid, '(a)') '   0.00000     P078: : :'
      WRITE(fid, '(a)') '   0.00000     P079: : :'
      WRITE(fid, '(a)') '   0.00000     P080: : :'
      WRITE(fid, '(a)') '   0.00000     P081: : :'
      WRITE(fid, '(a)') '   0.00000     P082: : :'
      WRITE(fid, '(a)') '   0.00000     P083:'
      WRITE(fid, '(a)') '   0.00000     P084: !=0 --> sets initial timestep if p12>0'
      WRITE(fid, '(a)') '   0.00000     P085: dt ratio if p84 !=0, for timesteps>0'
      WRITE(fid, '(a)') '   0.00000     P086: reserved'
      WRITE(fid, '(a)') '   0.00000     P087: : :'
      WRITE(fid, '(a)') '   0.00000     P088: : :'
      WRITE(fid, '(a)') '   0.00000     P089: : :   coarse grid weighting (default=10.'
      WRITE(fid, '(a)') '   0.00000     P090: : :'
      WRITE(fid, '(a)') '   0.00000     P091: : :'
      WRITE(fid, '(a)') '   0.00000     P092:'
      WRITE(fid, '(a)') '   20.0000     P093: Number of previous pressure solns saved'
      WRITE(fid, '(a)') '   9.00000     P094: start projecting velocity after p94 step'
      WRITE(fid, '(a)') '   9.00000     P095: start projecting pressure after p95 step'
      WRITE(fid, '(a)') '   0.00000     P096: : :   which saving algorithm 1 = discard'
      WRITE(fid, '(a)') '   0.00000     P097: : :   0 == > no iterative refinement'
      WRITE(fid, '(a)') '   0.00000     P098:'
      WRITE(fid, '(a)') '   3.00000     P099: dealiasing: <0--> off/3--> old/4--> new'
      WRITE(fid, '(a)') '   0.00000     P100:'
      WRITE(fid, '(a)') '   0.00000     P101: Number of additional modes to filter'
      WRITE(fid, '(a)') '   1.00000     P102: Dump out divergence at each time step'
      WRITE(fid, '(a)') '   0.01000     P103: weight of stabilizing filter (.01)'
      WRITE(fid, '(a)') '   0.00000     P104: : :'
      WRITE(fid, '(a)') '   0.00000     P105: : :'
      WRITE(fid, '(a)') '   0.00000     P106:'
      WRITE(fid, '(a)') '   0.00000     P107: !=0 --> add to h2 array in hlmhotz eqn'
      WRITE(fid, '(a)') '   0.00000     P108: : :'
      WRITE(fid, '(a)') '   0.00000     P109: : :'
      WRITE(fid, '(a)') '   0.00000     P110: : :'
      WRITE(fid, '(a)') '   0.00000     P111: : :'
      WRITE(fid, '(a)') '   0.00000     P112: : :'
      WRITE(fid, '(a)') '   0.00000     P113: : :'
      WRITE(fid, '(a)') '   0.00000     P114: : :'
      WRITE(fid, '(a)') '   0.00000     P115:'
      WRITE(fid, '(a)') '   0.00000     P116: !=0: x elements for fast tensor product'
      WRITE(fid, '(a)') '   0.00000     P117: !=0: y elements for fast tensor product'
      WRITE(fid, '(a)') '   0.00000     P118: !=0: z elements for fast tensor product'
      WRITE(fid, '(a)') '      4  Lines of passive scalar data follows2 CONDUCT; 2RHOCP'
      WRITE(fid, '(a)') '   1.00000       1.00000       1.00000       1.00000       1.00000'
      WRITE(fid, '(a)') '   1.00000       1.00000       1.00000       1.00000'
      WRITE(fid, '(a)') '   1.00000       1.00000       1.00000       1.00000       1.00000'
      WRITE(fid, '(a)') '   1.00000       1.00000       1.00000       1.00000'
      WRITE(fid, '(a)') '          13   LOGICAL SWITCHES FOLLOW'
      WRITE(fid, '(a)') ' T      IFFLOW'
      WRITE(fid, '(a)') ' F      IFHEAT'
      WRITE(fid, '(a)') ' T      IFTRAN'
      WRITE(fid, '(a)') ' T F F F F F F F F F F  IFNAV & IFADVC (convection in P.S. fields)'
      WRITE(fid, '(a)') ' F F T T T T T T T T T T  IFTMSH (IF mesh for this field is T mesh)'
      WRITE(fid, '(a)') ' F      IFAXIS'
      WRITE(fid, '(a)') ' F      IFSTRS'
      WRITE(fid, '(a)') ' F      IFSPLIT'
      WRITE(fid, '(a)') ' F      IFMGRID'
      WRITE(fid, '(a)') ' F      IFMODEL'
      WRITE(fid, '(a)') ' F      IFKEPS'
      WRITE(fid, '(a)') ' F      IFMVBD'
      WRITE(fid, '(a)') ' F      IFCHAR'
      WRITE(fid, '(a)') '   2.00000       2.00000      -1.00000      -1.00000     XFAC,YFAC,XZERO,YZERO'

   end subroutine initializeMeshFile

!------------------------------------------------------------------------------

   subroutine finalizeMeshFile (fid)
   
      IMPLICIT NONE
      ! input variables
      INTEGER, INTENT(IN) :: fid


      WRITE(fid, '(a)') '  ***** NO THERMAL BOUNDARY CONDITIONS *****'
      WRITE(fid, '(a)') '   0 PRESOLVE/RESTART OPTIONS  *****'
      WRITE(fid, '(a)') '   7         INITIAL CONDITIONS *****'
      WRITE(fid, '(a)') 'C Default'
      WRITE(fid, '(a)') 'C Default'
      WRITE(fid, '(a)') 'C Default'
      WRITE(fid, '(a)') 'C Default'
      WRITE(fid, '(a)') 'C Default'
      WRITE(fid, '(a)') 'C Default'
      WRITE(fid, '(a)') 'C Default'
      WRITE(fid, '(a)') '  ***** DRIVE FORCE DATA ***** BODY FORCE, FLOW, Q'
      WRITE(fid, '(a)') '   4                 Lines of Drive force data follow'
      WRITE(fid, '(a)') 'C'
      WRITE(fid, '(a)') 'C'
      WRITE(fid, '(a)') 'C'
      WRITE(fid, '(a)') 'C'
      WRITE(fid, '(a)') '  ***** Variable Property Data ***** Overrrides Parameter data.'
      WRITE(fid, '(a)') '   1 Lines follow.'
      WRITE(fid, '(a)') '   0 PACKETS OF DATA FOLLOW'
      WRITE(fid, '(a)') '  ***** HISTORY AND INTEGRAL DATA *****'
      WRITE(fid, '(a)') '   0   POINTS.  Hcode, I,J,H,IEL'
      WRITE(fid, '(a)') '  ***** OUTPUT FIELD SPECIFICATION *****'
      WRITE(fid, '(a)') '   6 SPECIFICATIONS FOLLOW'
      WRITE(fid, '(a)') '   T      COORDINATES'
      WRITE(fid, '(a)') '   T      VELOCITY'
      WRITE(fid, '(a)') '   T      PRESSURE'
      WRITE(fid, '(a)') '   T      TEMPERATURE'
      WRITE(fid, '(a)') '   F      TEMPERATURE GRADIENT'
      WRITE(fid, '(a)') '   0      PASSIVE SCALARS'
      WRITE(fid, '(a)') '  ***** OBJECT SPECIFICATION *****'
      WRITE(fid, '(a)') '       0 Surface Objects'
      WRITE(fid, '(a)') '       0 Volume  Objects'
      WRITE(fid, '(a)') '       0 Edge    Objects'
      WRITE(fid, '(a)') '       0 Point   Objects'

   end subroutine finalizeMeshFile

!------------------------------------------------------------------------------

   subroutine writeElement (fid, elem)

      IMPLICIT NONE
      ! input variables
      INTEGER,       INTENT(IN) :: fid
      TYPE(element), INTENT(IN) :: elem
      ! local variables

      WRITE(fid, '(a18,1x,i10,a4,i3,a1,a11,i5)') &
         '          ELEMENT', elem%num, ' [  ', 1, elem%groupL, ']    GROUP ', elem%group

      WRITE(fid, '(4(es14.6e2))') elem%x(1), elem%x(2), elem%x(3), elem%x(4)
      WRITE(fid, '(4(es14.6e2))') elem%y(1), elem%y(2), elem%y(3), elem%y(4)
      WRITE(fid, '(4(es14.6e2))') elem%z(1), elem%z(2), elem%z(3), elem%z(4)

      WRITE(fid, '(4(es14.6e2))') elem%x(5), elem%x(6), elem%x(7), elem%x(8)
      WRITE(fid, '(4(es14.6e2))') elem%y(5), elem%y(6), elem%y(7), elem%y(8)
      WRITE(fid, '(4(es14.6e2))') elem%z(5), elem%z(6), elem%z(7), elem%z(8)

   end subroutine writeElement

!------------------------------------------------------------------------------

   subroutine writeCurvedEdges (fid, elem)

      IMPLICIT NONE
      ! input variables
      INTEGER,       INTENT(IN) :: fid
      TYPE(element), INTENT(IN) :: elem
      ! local variables
      INTEGER :: j

      IF ( nEl < 1e3 ) THEN

         DO j = 1, 8 ! cycle on the six edges
            IF ( elem%curvedEdge(j) ) THEN
               WRITE(fid, '(i3,i3,f10.5,4(f14.5),5x,a1)') &
                  j, elem%num, elem%curvedEdgeR(j), 0d0, 0d0, 0d0, 0d0, 'C'
            ENDIF
         ENDDO

      ELSEIF ( nEl < 1e6 ) THEN

         DO j = 1, 8 ! cycle on the six edges
            IF ( elem%curvedEdge(j) ) THEN
               WRITE(fid, '(i2,i6,f10.5,4(f14.5),5x,a1)') &
                  j, elem%num, elem%curvedEdgeR(j), 0d0, 0d0, 0d0, 0d0, 'C'
            ENDIF
         ENDDO

      ELSE

         DO j = 1, 8 ! cycle on the six edges
            IF ( elem%curvedEdge(j) ) THEN
               WRITE(fid, '(i2,i10,f10.5,4(f14.5),5x,a1)') &
                  j, elem%num, elem%curvedEdgeR(j), 0d0, 0d0, 0d0, 0d0, 'C'
            ENDIF
         ENDDO

      ENDIF

   end subroutine writeCurvedEdges

!------------------------------------------------------------------------------

   subroutine writeBoundaryConditions (fid, elem)

      IMPLICIT NONE
      ! input variables
      INTEGER,       INTENT(IN) :: fid
      TYPE(element), INTENT(IN) :: elem
      ! local variables
      INTEGER :: j

      IF ( nEl < 1e3 ) THEN

         DO j = 1, 6 ! cycle on the six faces
            WRITE(fid, '(1x,a2,1x,i3,i3,f10.1,4(f14.5))') &
               elem%bcType(j), elem%num, j, elem%bcParameters(j,:)
         ENDDO

      ELSEIF ( nEl < 1e5 ) THEN

         DO j = 1, 6 ! cycle on the six faces
            WRITE(fid, '(1x,a2,1x,i5,i1,f10.1,4(f14.5))') &
               elem%bcType(j), elem%num, j, elem%bcParameters(j,:)
         ENDDO

      ELSE

         DO j = 1, 6 ! cycle on the six faces
            WRITE(fid, '(1x,a2,1x,i10,i1,f10.1,4(f14.5))') &
               elem%bcType(j), elem%num, j, elem%bcParameters(j,:)
         ENDDO


      ENDIF

   end subroutine writeBoundaryConditions



!==============================================================================

end program pipeMeshNek
