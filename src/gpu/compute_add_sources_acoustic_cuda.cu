/*
 !=====================================================================
 !
 !               S p e c f e m 3 D  V e r s i o n  3 . 0
 !               ---------------------------------------
 !
 !     Main historical authors: Dimitri Komatitsch and Jeroen Tromp
 !                              CNRS, France
 !                       and Princeton University, USA
 !                 (there are currently many more authors!)
 !                           (c) October 2017
 !
 ! This program is free software; you can redistribute it and/or modify
 ! it under the terms of the GNU General Public License as published by
 ! the Free Software Foundation; either version 3 of the License, or
 ! (at your option) any later version.
 !
 ! This program is distributed in the hope that it will be useful,
 ! but WITHOUT ANY WARRANTY; without even the implied warranty of
 ! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 ! GNU General Public License for more details.
 !
 ! You should have received a copy of the GNU General Public License along
 ! with this program; if not, write to the Free Software Foundation, Inc.,
 ! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 !
 !=====================================================================
*/

#include "mesh_constants_cuda.h"

/* ----------------------------------------------------------------------------------------------- */

// acoustic sources

/* ----------------------------------------------------------------------------------------------- */


// Converts source time function to the correct GPU precision, and adapts format for NB_RUNS_ON_ACOUSTIC_GPU option
void get_stf_for_gpu(field* stf_pre_compute, double* h_stf_pre_compute, int * run_number_of_the_source, int NSOURCES) {

  TRACE("get_stf_for_gpu");
  realw realw_to_field[NB_RUNS_ACOUSTIC_GPU];

  //Conversion to GPU precision
  //Converts source time function to the field format. The stf value is saved only into its corresponding run. For other runs, a zero will be added

  for (int i_source=0;i_source < NSOURCES;i_source++){
    for (int i_run=0;i_run < NB_RUNS_ACOUSTIC_GPU;i_run++)
      if (run_number_of_the_source[i_source] == i_run){
        realw_to_field[i_run]= (realw)h_stf_pre_compute[i_source];
      }
      else{
        realw_to_field[i_run] = 0.0f;
      }
      //function Make_field is overloaded to convert array of realw into field structure
      stf_pre_compute[i_source] = Make_field(realw_to_field);
  }
}

/* ----------------------------------------------------------------------------------------------- */

extern EXTERN_LANG
void FC_FUNC_(compute_add_sources_ac_cuda,
              COMPUTE_ADD_SOURCES_AC_CUDA)(long* Mesh_pointer,
                                           int* NSOURCESf,
                                           double* h_stf_pre_compute,int* run_number_of_the_source) {

  TRACE("compute_add_sources_ac_cuda");

  Mesh* mp = (Mesh*)(*Mesh_pointer); //get mesh pointer out of fortran integer container

  // check if anything to do
  if (mp->nsources_local == 0) return;

  int NSOURCES = *NSOURCESf;

  field* stf_pre_compute = (field*) malloc(NSOURCES * sizeof(field));
  get_stf_for_gpu(stf_pre_compute,h_stf_pre_compute,run_number_of_the_source,NSOURCES);

  // copies pre-computed source time factors onto GPU
  print_CUDA_error_if_any(cudaMemcpy(mp->d_stf_pre_compute,stf_pre_compute,
                                     NSOURCES*sizeof(field),cudaMemcpyHostToDevice),1877);
  free(stf_pre_compute);

  int num_blocks_x, num_blocks_y;
  get_blocks_xy(NSOURCES,&num_blocks_x,&num_blocks_y);

  dim3 grid(num_blocks_x,num_blocks_y);
  dim3 threads(NGLLX,NGLLY,NGLLZ);

  compute_add_sources_acoustic_kernel<<<grid,threads,0,mp->compute_stream>>>(mp->d_potential_dot_dot_acoustic,
                                                                              mp->d_ibool,
                                                                              mp->d_sourcearrays,
                                                                              mp->d_stf_pre_compute,
                                                                              mp->myrank,
                                                                              mp->d_islice_selected_source,
                                                                              mp->d_ispec_selected_source,
                                                                              mp->d_ispec_is_acoustic,
                                                                              mp->d_kappastore,
                                                                              NSOURCES);


  GPU_ERROR_CHECKING("compute_add_sources_ac_cuda");
}

/* ----------------------------------------------------------------------------------------------- */

extern EXTERN_LANG
void FC_FUNC_(compute_add_sources_ac_s3_cuda,
              COMPUTE_ADD_SOURCES_AC_s3_CUDA)(long* Mesh_pointer,
                                              int* NSOURCESf,
                                              double* h_stf_pre_compute,int* run_number_of_the_source) {

  TRACE("compute_add_sources_ac_s3_cuda");

  Mesh* mp = (Mesh*)(*Mesh_pointer); //get mesh pointer out of fortran integer container

  // check if anything to do
  if (mp->nsources_local == 0) return;

  int NSOURCES = *NSOURCESf;

  field* stf_pre_compute = (field*) malloc(NSOURCES * sizeof(field));
  get_stf_for_gpu(stf_pre_compute,h_stf_pre_compute,run_number_of_the_source,NSOURCES);

  // copies source time factors onto GPU
  print_CUDA_error_if_any(cudaMemcpy(mp->d_stf_pre_compute,stf_pre_compute,
                                     NSOURCES*sizeof(field),cudaMemcpyHostToDevice),55);

  free(stf_pre_compute);

  int num_blocks_x, num_blocks_y;
  get_blocks_xy(NSOURCES,&num_blocks_x,&num_blocks_y);

  dim3 grid(num_blocks_x,num_blocks_y);
  dim3 threads(NGLLX,NGLLY,NGLLZ);

  compute_add_sources_acoustic_kernel<<<grid,threads,0,mp->compute_stream>>>(mp->d_b_potential_dot_dot_acoustic,
                                                                              mp->d_ibool,
                                                                              mp->d_sourcearrays,
                                                                              mp->d_stf_pre_compute,
                                                                              mp->myrank,
                                                                              mp->d_islice_selected_source,
                                                                              mp->d_ispec_selected_source,
                                                                              mp->d_ispec_is_acoustic,
                                                                              mp->d_kappastore,
                                                                              NSOURCES);

  GPU_ERROR_CHECKING("compute_add_sources_ac_s3_cuda");
}


/* ----------------------------------------------------------------------------------------------- */

// acoustic adjoint sources

/* ----------------------------------------------------------------------------------------------- */


extern EXTERN_LANG
void FC_FUNC_(add_sources_ac_sim_2_or_3_cuda,
              ADD_SOURCES_AC_SIM_2_OR_3_CUDA)(long* Mesh_pointer,
                                              realw* h_source_adjoint,
                                              int* nrec,
                                              int* nadj_rec_local,
                                              int* NTSTEP_BETWEEN_READ_ADJSRC,
                                              int* it) {

  TRACE("add_sources_ac_sim_2_or_3_cuda");

  Mesh* mp = (Mesh*)(*Mesh_pointer); //get mesh pointer out of fortran integer container

  // checks
  if (*nadj_rec_local != mp->nadj_rec_local) exit_on_cuda_error("add_sources_ac_sim_type_2_or_3: nadj_rec_local not equal\n");

  // note: for acoustic simulations with fused wavefields, NB_RUNS_ACOUSTIC_GPU > 1
  //       and thus the number of adjoint sources might become different in future
  //       todo: not implemented yet for adjoint/kernel simulation
  //if (*nadj_rec_local/NB_RUNS_ACOUSTIC_GPU != mp->nadj_rec_local)
  //  exit_on_cuda_error("add_sources_ac_sim_type_2_or_3: nadj_rec_local not equal\n");

  // checks if anything to do
  if (mp->nadj_rec_local == 0) return;

  int num_blocks_x, num_blocks_y;
  get_blocks_xy(mp->nadj_rec_local,&num_blocks_x,&num_blocks_y);

  dim3 grid(num_blocks_x,num_blocks_y,1);
  dim3 threads(NGLLX,NGLLY,NGLLZ);

  int it_index = *NTSTEP_BETWEEN_READ_ADJSRC - (*it-1) % *NTSTEP_BETWEEN_READ_ADJSRC - 1 ;

  // copies extracted array values onto GPU
  if ( (*it-1) % *NTSTEP_BETWEEN_READ_ADJSRC==0){
    print_CUDA_error_if_any(cudaMemcpy(mp->d_source_adjoint,h_source_adjoint,
                                       mp->nadj_rec_local*NDIM*sizeof(field)*(*NTSTEP_BETWEEN_READ_ADJSRC),cudaMemcpyHostToDevice),99099);
  }

  // launches cuda kernel for acoustic adjoint sources
  add_sources_ac_SIM_TYPE_2_OR_3_kernel<<<grid,threads,0,mp->compute_stream>>>(mp->d_potential_dot_dot_acoustic,
                                                                                *nrec,it_index,*NTSTEP_BETWEEN_READ_ADJSRC,
                                                                                mp->d_source_adjoint,
                                                                                mp->d_hxir_adj,
                                                                                mp->d_hetar_adj,
                                                                                mp->d_hgammar_adj,
                                                                                mp->d_ibool,
                                                                                mp->d_ispec_is_acoustic,
                                                                                mp->d_ispec_selected_adjrec_loc,
                                                                                mp->nadj_rec_local,
                                                                                mp->d_kappastore);


  GPU_ERROR_CHECKING("add_sources_acoustic_SIM_TYPE_2_OR_3_kernel");
}