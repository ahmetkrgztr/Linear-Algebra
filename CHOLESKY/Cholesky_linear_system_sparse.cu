#include <stdio.h>
#include <stdlib.h>
#include <iostream>
#include <assert.h>

#include <cuda_runtime.h>
#include <cusparse_v2.h>

/********/
/* MAIN */
/********/
int main()
{
	// --- Initialize cuSPARSE
	cusparseHandle_t handle;	cusparseSafeCall(cusparseCreate(&handle));

	const int Nrows = 4;						// --- Number of rows
	const int Ncols = 4;						// --- Number of columns
	const int N     = Nrows;

	// --- Host side dense matrix
	double *h_A_dense = (double*)malloc(Nrows*Ncols*sizeof(*h_A_dense));
	
	// --- Column-major ordering
	h_A_dense[0] = 0.4612f;  h_A_dense[4] = -0.0006f;	h_A_dense[8]  = 0.3566f; h_A_dense[12] = 0.0f; 
	h_A_dense[1] = -0.0006f; h_A_dense[5] = 0.4640f;	h_A_dense[9]  = 0.0723f; h_A_dense[13] = 0.0f; 
	h_A_dense[2] = 0.3566f;  h_A_dense[6] = 0.0723f;	h_A_dense[10] = 0.7543f; h_A_dense[14] = 0.0f; 
	h_A_dense[3] = 0.f;		 h_A_dense[7] = 0.0f;		h_A_dense[11] = 0.0f;	 h_A_dense[15] = 0.1f; 

	// --- Create device array and copy host array to it
	double *d_A_dense;	gpuErrchk(cudaMalloc(&d_A_dense, Nrows * Ncols * sizeof(*d_A_dense)));
	gpuErrchk(cudaMemcpy(d_A_dense, h_A_dense, Nrows * Ncols * sizeof(*d_A_dense), cudaMemcpyHostToDevice));
	
	// --- Descriptor for sparse matrix A
	cusparseMatDescr_t descrA;		cusparseSafeCall(cusparseCreateMatDescr(&descrA));
	cusparseSafeCall(cusparseSetMatType		(descrA, CUSPARSE_MATRIX_TYPE_GENERAL));
	cusparseSafeCall(cusparseSetMatIndexBase(descrA, CUSPARSE_INDEX_BASE_ONE));  
	
	int nnz = 0;								// --- Number of nonzero elements in dense matrix
	const int lda = Nrows;						// --- Leading dimension of dense matrix
	// --- Device side number of nonzero elements per row
	int *d_nnzPerVector; 	gpuErrchk(cudaMalloc(&d_nnzPerVector, Nrows * sizeof(*d_nnzPerVector)));
	cusparseSafeCall(cusparseDnnz(handle, CUSPARSE_DIRECTION_ROW, Nrows, Ncols, descrA, d_A_dense, lda, d_nnzPerVector, &nnz));
	// --- Host side number of nonzero elements per row
	int *h_nnzPerVector = (int *)malloc(Nrows * sizeof(*h_nnzPerVector));
	gpuErrchk(cudaMemcpy(h_nnzPerVector, d_nnzPerVector, Nrows * sizeof(*h_nnzPerVector), cudaMemcpyDeviceToHost));

	printf("Number of nonzero elements in dense matrix = %i\n\n", nnz);
	for (int i = 0; i < Nrows; ++i) printf("Number of nonzero elements in row %i = %i \n", i, h_nnzPerVector[i]);
	printf("\n");

	// --- Device side dense matrix
	double *d_A;			gpuErrchk(cudaMalloc(&d_A, nnz * sizeof(*d_A)));
	int *d_A_RowIndices;	gpuErrchk(cudaMalloc(&d_A_RowIndices, (Nrows + 1) * sizeof(*d_A_RowIndices)));
	int *d_A_ColIndices;	gpuErrchk(cudaMalloc(&d_A_ColIndices, nnz * sizeof(*d_A_ColIndices)));
	
	cusparseSafeCall(cusparseDdense2csr(handle, Nrows, Ncols, descrA, d_A_dense, lda, d_nnzPerVector, d_A, d_A_RowIndices, d_A_ColIndices));

	// --- Host side dense matrix
	double *h_A = (double *)malloc(nnz * sizeof(*h_A));		
	int *h_A_RowIndices = (int *)malloc((Nrows + 1) * sizeof(*h_A_RowIndices));
	int *h_A_ColIndices = (int *)malloc(nnz * sizeof(*h_A_ColIndices));
	gpuErrchk(cudaMemcpy(h_A, d_A, nnz*sizeof(*h_A), cudaMemcpyDeviceToHost));
	gpuErrchk(cudaMemcpy(h_A_RowIndices, d_A_RowIndices, (Nrows + 1) * sizeof(*h_A_RowIndices), cudaMemcpyDeviceToHost));
	gpuErrchk(cudaMemcpy(h_A_ColIndices, d_A_ColIndices, nnz * sizeof(*h_A_ColIndices), cudaMemcpyDeviceToHost));
	
	printf("\nOriginal matrix in CSR format\n\n");
	for (int i = 0; i < nnz; ++i) printf("A[%i] = %.0f ", i, h_A[i]); printf("\n");

	printf("\n");
	for (int i = 0; i < (Nrows + 1); ++i) printf("h_A_RowIndices[%i] = %i \n", i, h_A_RowIndices[i]); printf("\n");

	for (int i = 0; i < nnz; ++i) printf("h_A_ColIndices[%i] = %i \n", i, h_A_ColIndices[i]);	
	
    // --- Allocating and defining dense host and device data vectors
	double *h_x	= (double *)malloc(Nrows * sizeof(double)); 
	h_x[0] = 100.0;  h_x[1] = 200.0; h_x[2] = 400.0; h_x[3] = 500.0;

	double *d_x;		gpuErrchk(cudaMalloc(&d_x, Nrows * sizeof(double)));   
    gpuErrchk(cudaMemcpy(d_x, h_x, Nrows * sizeof(double), cudaMemcpyHostToDevice));
	
	/******************************************/
	/* STEP 1: CREATE DESCRIPTORS FOR L AND U */
	/******************************************/
	cusparseMatDescr_t		descr_L = 0; 
	cusparseSafeCall(cusparseCreateMatDescr	(&descr_L)); 
	cusparseSafeCall(cusparseSetMatIndexBase	(descr_L, CUSPARSE_INDEX_BASE_ONE)); 
	cusparseSafeCall(cusparseSetMatType		(descr_L, CUSPARSE_MATRIX_TYPE_GENERAL)); 
	cusparseSafeCall(cusparseSetMatFillMode	(descr_L, CUSPARSE_FILL_MODE_LOWER)); 
	cusparseSafeCall(cusparseSetMatDiagType	(descr_L, CUSPARSE_DIAG_TYPE_NON_UNIT)); 
	
	/********************************************************************************************************/
	/* STEP 2: QUERY HOW MUCH MEMORY USED IN CHOLESKY FACTORIZATION AND THE TWO FOLLOWING SYSTEM INVERSIONS */
	/********************************************************************************************************/
	csric02Info_t info_A  = 0;	cusparseSafeCall(cusparseCreateCsric02Info(&info_A)); 
	csrsv2Info_t  info_L  = 0;	cusparseSafeCall(cusparseCreateCsrsv2Info (&info_L)); 
	csrsv2Info_t  info_Lt = 0;	cusparseSafeCall(cusparseCreateCsrsv2Info (&info_Lt)); 
	
	int pBufferSize_M, pBufferSize_L, pBufferSize_Lt;
	cusparseSafeCall(cusparseDcsric02_bufferSize(handle, N, nnz, descrA, d_A, d_A_RowIndices, d_A_ColIndices, info_A, &pBufferSize_M)); 
	cusparseSafeCall(cusparseDcsrsv2_bufferSize (handle, CUSPARSE_OPERATION_NON_TRANSPOSE, N, nnz, descr_L, d_A, d_A_RowIndices, d_A_ColIndices, info_L,  &pBufferSize_L)); 
	cusparseSafeCall(cusparseDcsrsv2_bufferSize (handle, CUSPARSE_OPERATION_TRANSPOSE,     N, nnz, descr_L, d_A, d_A_RowIndices, d_A_ColIndices, info_Lt, &pBufferSize_Lt)); 
	
	int pBufferSize = max(pBufferSize_M, max(pBufferSize_L, pBufferSize_Lt)); 
	void *pBuffer = 0;	gpuErrchk(cudaMalloc((void**)&pBuffer, pBufferSize)); 
	
	/******************************************************************************************************/
	/* STEP 3: ANALYZE THE THREE PROBLEMS: CHOLESKY FACTORIZATION AND THE TWO FOLLOWING SYSTEM INVERSIONS */
	/******************************************************************************************************/
	int structural_zero; 

	cusparseSafeCall(cusparseDcsric02_analysis(handle, N, nnz, descrA, d_A, d_A_RowIndices, d_A_ColIndices, info_A, CUSPARSE_SOLVE_POLICY_NO_LEVEL, pBuffer)); 
	
	cusparseStatus_t status = cusparseXcsric02_zeroPivot(handle, info_A, &structural_zero); 
	if (CUSPARSE_STATUS_ZERO_PIVOT == status){ printf("A(%d,%d) is missing\n", structural_zero, structural_zero); } 

	cusparseSafeCall(cusparseDcsrsv2_analysis(handle, CUSPARSE_OPERATION_NON_TRANSPOSE, N, nnz, descr_L, d_A, d_A_RowIndices, d_A_ColIndices, info_L,  CUSPARSE_SOLVE_POLICY_NO_LEVEL,  pBuffer)); 
	cusparseSafeCall(cusparseDcsrsv2_analysis(handle, CUSPARSE_OPERATION_TRANSPOSE,     N, nnz, descr_L, d_A, d_A_RowIndices, d_A_ColIndices, info_Lt, CUSPARSE_SOLVE_POLICY_USE_LEVEL, pBuffer)); 
	
	/*************************************/
	/* STEP 4: FACTORIZATION: A = L * L' */
	/*************************************/
	int numerical_zero; 

	cusparseSafeCall(cusparseDcsric02(handle, N, nnz, descrA, d_A, d_A_RowIndices, d_A_ColIndices, info_A, CUSPARSE_SOLVE_POLICY_NO_LEVEL, pBuffer)); 
	status = cusparseXcsric02_zeroPivot(handle, info_A, &numerical_zero); 
	if (CUSPARSE_STATUS_ZERO_PIVOT == status){ printf("L(%d,%d) is zero\n", numerical_zero, numerical_zero); } 
	
	printf("\nNon-zero elements in Cholesky matrix\n\n");
	gpuErrchk(cudaMemcpy(h_A, d_A, nnz * sizeof(double), cudaMemcpyDeviceToHost));
	for (int k=0; k<nnz; k++) printf("%f\n", h_A[k]);

	cusparseSafeCall(cusparseDcsr2dense(handle, Nrows, Ncols, descrA, d_A, d_A_RowIndices, d_A_ColIndices, d_A_dense, Nrows));

	printf("\nCholesky matrix\n\n");
    for(int i = 0; i < Nrows; i++) {
        std::cout << "[ ";
        for(int j = 0; j < Ncols; j++)
            std::cout << h_A_dense[i * Ncols + j] << " ";
        std::cout << "]\n";
    }

	/*********************/
	/* STEP 5: L * z = x */
	/*********************/
	// --- Allocating the intermediate result vector
	double *d_z;		gpuErrchk(cudaMalloc(&d_z, N * sizeof(double))); 
	   
	const double alpha = 1.; 
	cusparseSafeCall(cusparseDcsrsv2_solve(handle, CUSPARSE_OPERATION_NON_TRANSPOSE, N, nnz, &alpha, descr_L, d_A, d_A_RowIndices, d_A_ColIndices, info_L, d_x, d_z, CUSPARSE_SOLVE_POLICY_NO_LEVEL, pBuffer)); 
	
	/**********************/
	/* STEP 5: L' * y = z */
	/**********************/
	// --- Allocating the host and device side result vector
	double *h_y	= (double *)malloc(Ncols * sizeof(double)); 
	double *d_y;		gpuErrchk(cudaMalloc(&d_y, Ncols * sizeof(double))); 

	cusparseSafeCall(cusparseDcsrsv2_solve(handle, CUSPARSE_OPERATION_TRANSPOSE, N, nnz, &alpha, descr_L, d_A, d_A_RowIndices, d_A_ColIndices, info_Lt, d_z, d_y, CUSPARSE_SOLVE_POLICY_USE_LEVEL, pBuffer)); 

	cudaMemcpy(h_x, d_y, N * sizeof(double), cudaMemcpyDeviceToHost);
	printf("\n\nFinal result\n");
	for (int k=0; k<N; k++) printf("x[%i] = %f\n", k, h_x[k]);
}
