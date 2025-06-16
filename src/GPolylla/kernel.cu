#include "triangulation.cu"

// Here starts the gpu code!!!!!!!

typedef int bit_vector_d;

// device code, basic operations
__device__ int twin_d(halfEdge *HalfEdges, int e)
{
    return HalfEdges[e].twin;
}

__device__ int next_d(halfEdge *HalfEdges, int e)
{
    return HalfEdges[e].next;
}

__device__ int prev_d(halfEdge *HalfEdges, int e)
{
    return HalfEdges[e].prev;
}

__device__ bool is_border_face_d(halfEdge *HalfEdges, int e)
{
    return HalfEdges[e].is_border;
}

__device__ bool is_interior_face_d(halfEdge *HalfEdges, int e)
{
   return !is_border_face_d(HalfEdges, e);
}

__device__ int origin_d(halfEdge *HalfEdges, int e)
{
    return HalfEdges[e].origin;
}

__device__ int target_d(halfEdge *HalfEdges, int e)
{
    //this->origin(HalfEdges.at(e).twin);
    return origin_d(HalfEdges, twin_d(HalfEdges, e));
}

__device__ int incident_halfedge_d(int f)
{
    return 3*f;
}

__device__ int edge_of_vertex_d(vertex *vertices, int v)
{
    return vertices[v].incident_halfedge;
}

__device__ int CW_edge_to_vertex_d(halfEdge *HalfEdges, int e)
{   int twn, nxt;
    twn = twin_d(HalfEdges, e);
    nxt = next_d(HalfEdges, twn);
    return nxt;
}    

__device__ int CCW_edge_to_vertex_d(halfEdge *HalfEdges, int e)
{
    int twn, prv;
    prv = HalfEdges[e].prev;
    twn = HalfEdges[prv].twin;
    return twn;
}    

// Get the index of the face incident to halfedge e
__device__ int index_face_d(int e) {
    return e / 3;
}

// Get the region of face f
__device__ int region_face_d(int *triangle_regions, int f, int num_regions) {
    if(triangle_regions != nullptr && f < num_regions)
        return triangle_regions[f];
    return 0; // default region
}




#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true)
{
   if (code != cudaSuccess) 
   {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

#define kernelCallCheck() \
	{ gpuErrchk( cudaPeekAtLastError() ); \
        gpuErrchk( cudaDeviceSynchronize() ); } 

#include <assert.h>
#include <cub/cub.cuh> 
#define BSIZE 1024


// Compute the distante of edge e
__device__ float distance_d(halfEdge *HalfEdges, vertex *Vertices, int e){
    float x1 = Vertices[origin_d(HalfEdges, e)].x;
    float y1 = Vertices[origin_d(HalfEdges, e)].y;
    float x2 = Vertices[target_d(HalfEdges, e)].x;
    float y2 = Vertices[target_d(HalfEdges, e)].y;

    //printf ("distance_d: %i %f %f %f %f\n", e, (float) x1, (float) y1, (float) x2, (float) y2);
    //printf ("origin_d: %i %f %f and target_d: %i %f %f\n", origin_d(HalfEdges, e), (float) x1, (float) y1, target_d(HalfEdges, e), (float) x2, (float) y2);

    return powf(x1-x2,2) + powf(y1-y2,2);
}

__device__ int Equality(double a, double b, double epsilon)
{
  return fabs(a - b) < epsilon;
}
 
__device__ int GreaterEqualthan(double a, double b, double epsilon){
        return Equality(a,b,epsilon) || a > b;
}

__device__ int compute_max_edge_d(halfEdge *HalfEdges, vertex *Vertices, int e){
    double epsion = 0.0000000001f;
    float l0 = distance_d(HalfEdges, Vertices, e); //min
    float l1 = distance_d(HalfEdges, Vertices, next_d(HalfEdges, e)); //mid
    float l2 = distance_d(HalfEdges, Vertices, prev_d(HalfEdges, e)); //max

    /*float m1 = fmaxf(dist0, dist1);
    float m2 = fmaxf(m1, dist2);    

    //__syncthreads();
    //printf ("off: %i dist0: %f, dist1: %f, dist2: %f, m1: %f, m2: %f\n", e, (float) dist0, (float) dist1, (float) dist2, (float) m1, (float) m2);

    //if (m1 == m2)
    //    printf ("off: %i dist0: %f, dist1: %f, dist2: %f, m1: %f, m2: %f\n", e, (float) dist0, (float) dist1, (float) dist2, (float) m1, (float) m2);

    if(m2 == dist0)
        return e;
    else if(m2 == dist1)
        return next_d(HalfEdges, e);
    else
        return prev_d(HalfEdges, e);
    return -1;*/

    __syncthreads();
    // compare two numbers at a time
   //if((l0 >= l1 && l1 >= l2) || (l0 >= l2 && l2 >= l1))
   if( (GreaterEqualthan(l0,l1,epsion) && GreaterEqualthan(l1,l2,epsion)) || ( GreaterEqualthan(l0,l2,epsion) && GreaterEqualthan(l2,l1,epsion)))
   {
           return e;
   }
   //else if((l1 >= l0 && l0 >= l2) || (l1 >= l2 && l2 >= l0))
   else if((GreaterEqualthan(l1,l0,epsion) && GreaterEqualthan(l0,l2,epsion)) || ( GreaterEqualthan(l1,l2,epsion) && GreaterEqualthan(l2,l0,epsion)))
   {
           return next_d(HalfEdges, e);
   }
   else
   {
           return prev_d(HalfEdges, e);
   }
   __syncthreads();

}

__device__ bool is_frontier_edge_d(halfEdge *halfedges, bit_vector_d *max_edges, const int e, 
                                   int *triangle_regions = nullptr, int num_regions = 0, bool use_regions = false)
{
    int twin = twin_d(halfedges, e);
    bool is_border_edge = is_border_face_d(halfedges, e) || is_border_face_d(halfedges, twin);
    bool is_not_max_edge = !(max_edges[e] || max_edges[twin]);
    
    bool is_region_boundary = false;
    if (use_regions && triangle_regions != nullptr) {
        int face1 = index_face_d(e);
        int face2 = index_face_d(twin);
        int region1 = region_face_d(triangle_regions, face1, num_regions);
        int region2 = region_face_d(triangle_regions, face2, num_regions);
        is_region_boundary = (region1 != region2);
    }
    
    if(is_border_edge || is_not_max_edge || is_region_boundary)
        return 1;
    else
        return 0;
}

__global__ void label_phase(halfEdge *halfedges, bit_vector_d *max_edges, bit_vector_d *frontier_edges, int n,
                           int *triangle_regions = nullptr, int num_regions = 0, bool use_regions = false){
    int off = threadIdx.x + blockDim.x*blockIdx.x;
    if (off < n){
        frontier_edges[off] = 0;
        if(is_frontier_edge_d(halfedges, max_edges, off, triangle_regions, num_regions, use_regions))
            frontier_edges[off] = 1;
        //printf("off: %i, frontier_edges: %i\n", off, frontier_edges[off]);
    }
}

__global__ void label_edges_max_d(bit_vector_d *output, vertex *Vertices, halfEdge *HalfEdges, int n)
{
    int off = (blockIdx.x * blockDim.x + threadIdx.x);
    if(off < n)
    {
        int edge_max_index = compute_max_edge_d(HalfEdges, Vertices, incident_halfedge_d(off));
        __syncthreads();
        //output[off] = max;
        //output[off] = 0;
        //printf("thread: %i, edge_max_index: %i\n", off, (int)edge_max_index);
        //atomicAdd(output+edge_max_index, 1);
        output[edge_max_index] = 1;
    }
}

__device__ bool is_seed_edge_d(halfEdge *HalfEdges, bit_vector_d *max_edges, int e,
                               int *triangle_regions = nullptr, int num_regions = 0, bool use_regions = false){
    int twin = twin_d(HalfEdges, e);

    bool is_terminal_edge = (is_interior_face_d(HalfEdges, twin) &&  (max_edges[e] && max_edges[twin]) );
    bool is_terminal_border_edge = (is_border_face_d(HalfEdges, twin) && max_edges[e]);
    
    bool is_terminal_region_edge = false;
    if (use_regions && triangle_regions != nullptr) {
        int face1 = index_face_d(e);
        int face2 = index_face_d(twin);
        int region1 = region_face_d(triangle_regions, face1, num_regions);
        int region2 = region_face_d(triangle_regions, face2, num_regions);
        bool is_region_boundary = (region1 != region2);
        is_terminal_region_edge = (is_region_boundary && max_edges[e]);
    }

    if( (is_terminal_edge && e < twin ) || is_terminal_border_edge || is_terminal_region_edge){
        return true;
    }

    return false;
}

__global__ void seed_phase_d(halfEdge *HalfEdges, bit_vector_d *max_edges, half *seed_edges, int n,
                             int *triangle_regions = nullptr, int num_regions = 0, bool use_regions = false){
    int x = threadIdx.x + blockIdx.x * blockDim.x; 
    // Calculate the row index of the Pd element, denote by y
    int y = threadIdx.y + blockIdx.y * blockDim.y;
    int off = x + y * blockDim.x * gridDim.x;
    if (off < n){
        //seed_edges[off] = 0;
        if(is_interior_face_d(HalfEdges, off) && is_seed_edge_d(HalfEdges, max_edges, off, triangle_regions, num_regions, use_regions))
            seed_edges[off] = __float2half(1.0f);
        }
}


__global__ void compaction_d(int *output, int *input, half *condition, int n){
    int off = threadIdx.x + blockDim.x*blockIdx.x;
    //printf("hola %i %i %i\n", off, input[off], condition[off]);
    int index = input[off];
    if (off < n){
        if ((int)condition[off] ==  1)
            output[index] = off;//*/
        //printf("hola %i %i %i %i\n", off, output[input[off]], input[off], condition[off]);
    }
}

int scan(int *d_out, int *d_in, int num_items){
    int *len = new int[1];
    // Determine temporary device storage requirements
    void     *d_temp_storage = NULL;
    size_t   temp_storage_bytes = 0;
    /*int *d_scan, *d_out;
    cudaMalloc(&d_out, sizeof(int)*num_items);
    cudaMalloc(&d_scan, sizeof(int)*num_items);*/
    cub::DeviceScan::ExclusiveSum(d_temp_storage, temp_storage_bytes, d_in, d_out, num_items);
    // Allocate temporary storage
    cudaMalloc(&d_temp_storage, temp_storage_bytes);
    // Run exclusive prefix sum
    cub::DeviceScan::ExclusiveSum(d_temp_storage, temp_storage_bytes, d_in, d_out, num_items);
    gpuErrchk( cudaDeviceSynchronize() );
    cudaMemcpy(len, d_out+num_items-1, sizeof(int), cudaMemcpyDeviceToHost);
    //gpuErrchk( cudaDeviceSynchronize() );
    return *len;
}


__device__ int search_next_frontier_edge_d(halfEdge *HalfEdges, bit_vector_d *frontier_edges, const int e)
{
    int nxt = e;
    while(!frontier_edges[nxt])
    {
        nxt = CW_edge_to_vertex_d(HalfEdges, nxt);
    }  
    return nxt;
}

__device__ int search_prev_frontier_edge_d(halfEdge *HalfEdges, bit_vector_d *frontier_edges, const int e)
{
    int prv = e;
    while(!frontier_edges[prv])
    {
        prv = CCW_edge_to_vertex_d(HalfEdges, prv);
    }  
    return prv;
}

__global__ void travel_phase_d(halfEdge *output, halfEdge *HalfEdges, bit_vector_d *max_edges, bit_vector_d *frontier_edges, int n){
    int off = threadIdx.x + blockIdx.x*blockDim.x;
    if (off < n){
        output[off] = HalfEdges[off];
        //printf ("aca-gpu %i\n", off);
        //if (is_frontier_edge_d(HalfEdges,max_edges,off)){
            output[off].next = search_next_frontier_edge_d(HalfEdges,frontier_edges,next_d(HalfEdges,off));
            output[off].prev = search_prev_frontier_edge_d(HalfEdges,frontier_edges,prev_d(HalfEdges,off));
        /*}else{
            output[off].next = search_next_frontier_edge_d(HalfEdges,frontier_edges,next_d(HalfEdges,off));
            output[off].prev = search_prev_frontier_edge_d(HalfEdges,frontier_edges,prev_d(HalfEdges,off));
        }*/
    }
}



// cub version of the scan parallel
template <typename T>
void scan_parallel_cub(T *out, T *in, int n) {
    void     *d_temp_storage = NULL;
    size_t   temp_storage_bytes = 0;
    cub::DeviceScan::ExclusiveSum(d_temp_storage, temp_storage_bytes, in, out, n); //kernelCallCheck();
    // Allocate temporary storage*/
    cudaMalloc(&d_temp_storage, temp_storage_bytes); //kernelCallCheck();
    // Run exclusive prefix sum
    cub::DeviceScan::ExclusiveSum(d_temp_storage, temp_storage_bytes, in, out, n); //kernelCallCheck();
}

template <typename T>
static __device__ T one() {
  	return T{1};
}

template <typename T>
static __device__ T zero() {
  	return T{0};
}

#define WARPSIZE 32
#define WARP_PER_BLOCK 32
#define SEGMENT_SIZE 256 * WARP_PER_BLOCK
#define BLOCK_DIM WARP_PER_BLOCK * WARPSIZE

#include <cuda.h>
#include <mma.h>
#include <cuda_fp16.h>
#include <cub/cub.cuh>
using namespace nvcuda;
static const int M              = 16;
static const int N              = 16;
static const int K              = 16;
static const int WMMA_TILE_SIZE = (M * N);

template <typename T>
__global__ void add_partial_sums_2(T *output, half *d_in, T *sums_warp, T *sums_block, int num_elements) {
	const int offset = threadIdx.x + blockIdx.x * blockDim.x;
	//const int globalWarpIdx = (threadIdx.x + blockDim.x * blockIdx.x)/WARPSIZE;
	const int globalSegmentIdx = offset >> 13; // /8192;
	const int globalWarpIdx = offset >> 8; // /256
	if (offset < num_elements) {
		output[offset+1] = (T)d_in[offset] + sums_warp[globalWarpIdx] + sums_block[globalSegmentIdx];
		//printf("%i %i %i %i\n",offset,(int)partial_sums[offset],globalSegmentIdx,(int)segmented_partial_sums[globalSegmentIdx]);
	}
}

// Compute scan using Tensor Cores
//template <int SEGMENT_SIZE, int WARPS_PER_BLOCK, int BLOCK_DIM>
template <typename T, typename V>
static __global__ void compute_wmma_segmented_prefixsum_256n_block_ps_2(V *d_out, T *sums_warp, T *sums_block, V *d_in, int num_segments) {
	
	T acc = 0;
	//__shared__ T partial_acc;
	__shared__ half u_frag_s[WMMA_TILE_SIZE];
	__shared__ half l_frag_s[WMMA_TILE_SIZE];
	__shared__ half la_mat_s[SEGMENT_SIZE];
	//int acc = 0; // only use the first 16

	//__shared__ V l_sum[WARP_PER_BLOCK];
	//__shared__ V l_out[SEGMENT_SIZE];
	
	const int localWarpIdx = threadIdx.x >> 5;// WARPSIZE;
	const int local_offset = localWarpIdx * WMMA_TILE_SIZE;
	//const int laneid = threadIdx.x % WARPSIZE;
	//const int globalSegmentIdx = (threadIdx.x + blockDim.x * blockIdx.x)/SEGMENT_SIZE;
	const int globalWarpIdx = (threadIdx.x + blockDim.x * blockIdx.x) >> 5; //WARPSIZE;
	const int offset = local_offset + blockIdx.x*SEGMENT_SIZE; //global_offset + (+ localWarpIdx) * WMMA_TILE_SIZE;
	
	#pragma unroll
	for (int idx = threadIdx.x; idx < WMMA_TILE_SIZE; idx += BLOCK_DIM) {
		const auto ii = idx / N;
		const auto jj = idx % N;
		u_frag_s[idx] = ii <= jj ? one<half>() : zero<half>();
		l_frag_s[idx] = ii <= jj ? zero<half>() : one<half>();
	}
	
	__syncthreads();
	
	wmma::fragment<wmma::matrix_a, M, N, K, half, wmma::row_major> a_frag;
	wmma::fragment<wmma::matrix_b, M, N, K, half, wmma::row_major> b_frag;
	wmma::fragment<wmma::matrix_b, M, N, K, half, wmma::row_major> u_frag;
	wmma::fragment<wmma::matrix_a, M, N, K, half, wmma::row_major> l_frag;
	wmma::fragment<wmma::matrix_b, M, N, K, half, wmma::row_major> o_frag;
	wmma::fragment<wmma::accumulator, M, N, K, half> la_frag;
	wmma::fragment<wmma::matrix_a, M, N, K, half, wmma::row_major> la_mat_frag;
	wmma::fragment<wmma::accumulator, M, N, K, half> au_frag;
	wmma::fragment<wmma::accumulator, M, N, K, half> out_frag;
	
	wmma::load_matrix_sync(u_frag, u_frag_s, 16);
	wmma::load_matrix_sync(l_frag, l_frag_s, 16);
	wmma::fill_fragment(o_frag, one<half>());
	wmma::fill_fragment(out_frag, zero<half>());

	wmma::fill_fragment(out_frag, zero<half>());
	wmma::fill_fragment(la_frag, zero<half>());
	wmma::load_matrix_sync(a_frag, d_in + offset, 16);
	wmma::load_matrix_sync(b_frag, d_in + offset, 16);

	wmma::mma_sync(au_frag, a_frag, u_frag, out_frag);
	wmma::mma_sync(la_frag, l_frag, b_frag, la_frag);

	// store accumulator la_frag into shared memory and load it into
	// matrix_a
	// fragment la_mat_frag
	wmma::store_matrix_sync(la_mat_s + local_offset, la_frag, 16, wmma::mem_row_major);
	wmma::load_matrix_sync(la_mat_frag, la_mat_s + local_offset, 16);

	wmma::mma_sync(out_frag, la_mat_frag, o_frag, au_frag);

	wmma::store_matrix_sync(d_out + offset, out_frag, 16, wmma::mem_row_major);
	//wmma::store_matrix_sync(l_out + local_offset, out_frag, 16, wmma::mem_row_major);

	__syncthreads();
	// then, do the scan on the warp accumulation
	if (threadIdx.x < WARP_PER_BLOCK) {
		acc = d_out[threadIdx.x*WMMA_TILE_SIZE + blockIdx.x*SEGMENT_SIZE + WMMA_TILE_SIZE - 1];
		//printf("-> %i %i %i\n",threadIdx.x, threadIdx.x*256 + blockIdx.x*8192 + 255, (int)acc);
	}
	__syncthreads();
    // Specialize WarpScan for type T
    typedef cub::WarpScan<T> WarpScan;
    // Allocate WarpScan shared memory for WARP_PER_BLOCK warps
    __shared__ typename WarpScan::TempStorage temp_storage[WARP_PER_BLOCK];
    // Obtain one input item per thread
    // Compute inclusive warp-wide prefix sums
	//__syncthreads();
    WarpScan(temp_storage[globalWarpIdx]).InclusiveSum(acc, acc);
	__syncthreads(); 

	if (threadIdx.x < WARP_PER_BLOCK - 1) {
		sums_warp[threadIdx.x+blockIdx.x*WARP_PER_BLOCK + 1] = acc;
	}
	__syncthreads();

	// store the partial sum of the current warp in shared memory
	if(threadIdx.x == WARP_PER_BLOCK - 1) {
		sums_block[blockIdx.x] = acc; //(T) sums_warp[WARP_PER_BLOCK];// acc;//temp_storage[threadIdx.x];
		if (blockIdx.x == 0) {
			sums_warp[0] = 0;
		}
	}
}

// scan parallel calcule the prefix sum using CUDA-TC programming from the array in and write the result in out
template <typename T>
void scan_parallel_tc_2(T *out, half *in, int n) {
	int num_segments = (n + 255) >> 8; //256;
	int num_block = (n + 8191) >> 13; //8192; //(n + SEGMENT_SIZE - 1) / SEGMENT_SIZE; //(n + 32 - 1)/32 + 1; //
    dim3 blockDim(BLOCK_DIM,1,1);
    dim3 gridDim(num_block,1,1);
	T *sums_block;
	T *sums_warp;
	half *sums_thread;
	cudaMalloc(&sums_block,sizeof(T)*num_block);
	cudaMalloc(&sums_warp,sizeof(T)*(num_segments));
	cudaMalloc(&sums_thread,sizeof(half)*n);
    compute_wmma_segmented_prefixsum_256n_block_ps_2<T,half><<<gridDim, blockDim>>>(sums_thread, sums_warp, sums_block, in, n); kernelCallCheck();
    cudaDeviceSynchronize();
	
	T *aux;
	cudaMalloc(&aux,sizeof(T)*num_block);
	scan_parallel_cub<T>(aux,sums_block,num_block); kernelCallCheck();
	add_partial_sums_2<T><<<(n+BSIZE-1)/BSIZE, BSIZE>>>(out, sums_thread, sums_warp, aux, n); kernelCallCheck(); //<256, SEGMENT_SIZE>*/
    cudaDeviceSynchronize();
}


__global__ void kernel (bit_vector_d *d_in, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
       printf ("in[%i] = %i\n", i, d_in[i]);
    }
}
__global__ void print_all_halfedges(halfEdge *HalfEdges, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
 //      printf ("halfedge[%i] = %i %i %i %i %i %i \n", i, HalfEdges[i].origin, target_d(HalfEdges,i), HalfEdges[i].twin, HalfEdges[i].next, HalfEdges[i].prev, HalfEdges[i].is_border);
        printf ("[%i, %i, %i],\n", i, HalfEdges[i].origin, target_d(HalfEdges,i));
    }
}




__device__ int degree_d(halfEdge *HalfEdges, vertex *vertices, int v)
{
    int e_curr = edge_of_vertex_d(vertices, v);
    int e_next = CCW_edge_to_vertex_d(HalfEdges, e_curr);
    int adv = 1;
    while (e_next != e_curr)
    {
        //printf("aca13 %i %i %i %i\n", origin_d(HalfEdges,e_curr), target_d(HalfEdges,e_curr), origin_d(HalfEdges,e_next), target_d(HalfEdges,e_next));
        e_next = CCW_edge_to_vertex_d(HalfEdges, e_next);
        adv++;
    }
    return adv;
}



//Given a barrier-edge tip v, return the middle edge incident to v
//The function first calculate the degree of v - 1 and then divide it by 2, after travel to until the middle-edge
//input: vertex v
//output: edge incident to v
__device__ int calculate_middle_edge_d(halfEdge *HalfEdges, bit_vector_d *frontier_edges, vertex *vertices, const int v){
    //print x
    int frontieredge_with_bet = search_next_frontier_edge_d(HalfEdges, frontier_edges, edge_of_vertex_d(vertices, v));
    int internal_edges = degree_d(HalfEdges, vertices, v) - 1; //internal-edges incident to v
    int adv = (internal_edges%2 == 0) ? internal_edges/2 - 1 : internal_edges/2 ;
    int nxt = CW_edge_to_vertex_d(HalfEdges, frontieredge_with_bet);
    //back to traversing the edges of v_bet until select the middle-edge
    while (adv != 0){
        nxt = CW_edge_to_vertex_d(HalfEdges, nxt);
        adv--;
    }
    return nxt;
}

//Return the number of frontier edges of a vertex
__device__ int count_frontier_edges_d(halfEdge *HalfEdges, bit_vector_d *frontier_edges, vertex *vertices, int v){
    int e = edge_of_vertex_d(vertices, v);
    int count = 0;
    do{
        if(frontier_edges[e] == 1)
            count++;
        e = CW_edge_to_vertex_d(HalfEdges, e);
    }while(e != edge_of_vertex_d( vertices, v));
    //if (count == 1)
    //    printf("--> %i %i\n",origin_d(HalfEdges,v),target_d(HalfEdges,v));
    return count;
}

    // new repair phase
__global__ void label_extra_frontier_edge_d(halfEdge *HalfEdges, bit_vector_d *frontier_edges, vertex *vertices, half *seed_edges, int n){
    int v = threadIdx.x + blockDim.x*blockIdx.x;
    if (v < n){

        if(count_frontier_edges_d(HalfEdges, frontier_edges, vertices, v) == 1){
        //if (v == 80){
            //middle edge that contains v_bet
            int middle_edge = calculate_middle_edge_d(HalfEdges, frontier_edges, vertices, v);

            //middle edge that contains v_bet
            int t1 = middle_edge;
            //int t1 = v;
            //int t2 = twin_d(HalfEdges, t1);
            int t2 = twin_d(HalfEdges, middle_edge);

            //edges of middle-edge are labeled as frontier-edge
            frontier_edges[t1] = 1;
            frontier_edges[t2] = 1;

            seed_edges[t1] = __float2half(1.0f);
            seed_edges[t2] = __float2half(1.0f);
        }
    }  
}

/*

//Travel in CCW order around the edges of vertex v from the edge e looking for the next frontier edge
__global__ void search_frontier_edge_d(int *output, halfEdge *HalfEdges, bit_vector_d *frontier_edges, int *seed_edges, int n)
{
    //int off = threadIdx.x + blockIdx.x*blockDim.x;
    
    int x = threadIdx.x + blockIdx.x * blockDim.x; 
    // Calculate the row index of the Pd element, denote by y
    int y = threadIdx.y + blockIdx.y * blockDim.y;
    int off = x + y * blockDim.x * gridDim.x;
    if (off < n){
        int nxt = seed_edges[off];
        //printf("%i %i\n",off,seed_edges[off]);
        while(!frontier_edges[nxt])
        {
            nxt = CW_edge_to_vertex_d(HalfEdges, nxt);
        }  
        output[off] = nxt;
    }
}

*/

__global__ void search_frontier_edge_d(halfEdge *HalfEdges, bit_vector_d *frontier_edges,  half *seed_edges, int n)
{
    int off = threadIdx.x + blockIdx.x*blockDim.x;
    if (off < n){
        if(__half2float(seed_edges[off]) == 1.0f){
            int nxt = off;
            //printf("%i %f\n",off,__half2float(seed_edges[off]));
            while(!frontier_edges[nxt])
            {
                nxt = CW_edge_to_vertex_d(HalfEdges, nxt);
            }  
            if(nxt != off)
                seed_edges[off] = __float2half(0.0f);
            seed_edges[nxt] = __float2half(1.0f);
            //printf("%i %i\n",off,nxt);
        }
    }
}

/*
__global__ void overwrite_seed_d(halfEdge *HalfEdges, int *seed_edges, int n){
        int i = threadIdx.x + blockIdx.x * blockDim.x; 
        if (i < n){        
            
            int e_init = seed_edges[i];
            int min_ind = e_init;

            int e_curr = next_d(HalfEdges, e_init);
            while(e_init != e_curr){

                min_ind = min(min_ind, e_curr);
                //printf("pene %i %i %i %i\n",i,e_curr,min_ind,e_init);
                //if (e_curr < min_ind){
                //    min_ind = e_curr;
                //}
                e_curr = next_d(HalfEdges, e_curr);
            }
            //printf("aca %i %i %i\n", i ,e_init,min_ind);
            seed_edges[i] = min_ind;
        }  
}
*/

//Esto funciona usando bitvectors
__global__ void overwrite_seed_d(halfEdge *HalfEdges, half *seed_edges, int n){
    int i = threadIdx.x + blockIdx.x * blockDim.x; 
    if (i < n){        
        if(__half2float(seed_edges[i]) == 1.0f){
            int e_init = i;
            int min_ind = e_init;
            int e_curr = next_d(HalfEdges, e_init);
            while(e_init != e_curr){
                min_ind = min(min_ind, e_curr);
                e_curr = next_d(HalfEdges, e_curr);
            }
            //printf("overwrite_seed_d %i %i %i\n", i ,e_init,min_ind);
            
            if(min_ind != i){
                seed_edges[i] = __float2half(0.0f);
            }
            seed_edges[min_ind] = __float2half(1.0f);
        }
    }  
}
