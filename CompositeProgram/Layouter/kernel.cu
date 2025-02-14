
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <iostream>
#include <stdio.h>
#include <string>
#include <time.h>   

#include "room.h"
#include "cudaroom.cuh"
#include "utils.cuh"
#include "constrainTerms.cuh"
#include "hostUtils.h"

using namespace std;

#define THREADHOLD_T 0.7

const unsigned int nBlocks = 1;
const unsigned int nThreads = 32;//it's werid
const unsigned int WHICH_GPU = 0;

struct sharedWrapper;
extern __shared__ sharedWrapper sWrapper[];
struct sharedWrapper {
	int nTimes;
	sharedRoom *wRoom;//1
	singleObj *wObjs;//nblocks
	float * obstacleVertices;//1
	float *wFloats;//1
	int *wPairRelation;//1
	float * resTransAndRot;//1 for all objs and all blocks
};
struct maskWrapper {
	unsigned char *initialMask;//1
	unsigned char *wMask;//nblocks
	unsigned char* backMask;//nblocks
	float * wmaskArea;//nblocks * 2
};
struct objMaskWrapper {
	unsigned maskSize;//in byte
	unsigned char * objMask;
};
void setUpDevices() {
	int deviceCount = 0;
	cudaGetDeviceCount(&deviceCount);
	if (WHICH_GPU <= deviceCount) {
		cudaError_t err = cudaSetDevice(WHICH_GPU);
		if (err != cudaSuccess)
			cout << "CUDA error:" << cudaGetErrorString(err) << endl;
	}
	else {
		cout << "Invalid GPU device " << WHICH_GPU << endl;
		exit(-1);
	}
	int wgpu;
	cudaGetDevice(&wgpu);
	cudaDeviceReset();
}
__device__
void changeTemparature(float * temparature) {
	int t1 = get_int_random(nBlocks);
	int t2 = t1;
	while (t2 == t1)
		t2 = get_int_random(nBlocks);
	float tmp = temparature[t1];
	temparature[t1] = temparature[t2];
	temparature[t2] = tmp;
}

__device__
void random_along_wall(sharedRoom * room, singleObj * obj) {
	wall * swall = &room->deviceWalls[get_int_random(room->wallNum)];
	float mwidth, mheight;
	if (get_int_random(2) == 0) {
		mwidth = obj->objWidth; mheight = obj->objHeight;
		set_obj_zrotation(obj, 0);
	}
	else {
		mwidth = obj->objHeight; mheight = obj->objWidth;
		set_obj_zrotation(obj, PI / 2);
	}

	float width_ran = swall->width - mwidth, height_ran = swall->width - mheight;
	float rh, rw;
	int mp = (swall->translation[0] >0 || swall->translation[1]>0) ? -1 : 1;
	if (fabsf(swall->b) < 0.01) {
		rh = min(swall->vertices[1], swall->vertices[3]) + get_float_random(height_ran) + obj->boundingBox.height / 2;
		set_obj_translation(room, obj, swall->translation[0] + mp * (mwidth / 2 + 0.01), rh);
	}
	else if (fabsf(swall->a) < 0.01) {
		rw = min(swall->vertices[0], swall->vertices[2]) + get_float_random(width_ran) + obj->boundingBox.width / 2;
		set_obj_translation(room, obj, rw, swall->translation[1] + mp * (mheight / 2 + 0.01));
	}
	else {
		rw = swall->vertices[0] + get_float_random(width_ran) + mwidth / 2;
		float y = (-swall->c - swall->a * rw) / swall->b;
		float tk = swall->b / swall->a, tb = y - tk * rw;
		float axbyc = mwidth / 2 * sqrtf(swall->a * swall->a + swall->b * swall->b);
		float tx = (axbyc - swall->c - swall->b * tb) / (swall->a + swall->b * tk);
		float ty = tk * tx + tb;
		if (ty > room->half_height || ty<-room->half_height) {
			tx = -tx; ty = tk * tx + tb;
		}
		//if(set_obj_translation(room, obj, tx, ty))
		//    printf("%f, %f\n", obj->translation[0], obj->translation[1]);
		set_obj_zrotation(obj, swall->zrotation);
	}
}



__device__
void initial_assignment(sharedRoom* room, singleObj * objs,
						unsigned char* initialMask, unsigned char * mask, unsigned char * backupMask,
						float * wmaskArea, float* tmpSlot, objMaskWrapper* objMaskArray) {
	if (threadIdx.x < room->objctNum) {
		singleObj * obj = &objs[threadIdx.x];
		if (obj->adjoinWall)
			random_along_wall(room, obj);

		else if (obj->alignedTheWall)
			set_obj_zrotation(obj, room->deviceWalls[get_int_random(room->wallNum)].zrotation);

		//INITIALIZE COST
		int singleSize = room->objctNum * 4 + 1;
		for (int i = 0; i<MAX_KEPT_RES; i++) {
			sWrapper[0].resTransAndRot[singleSize*i + threadIdx.x * 4] = INFINITY;
		}
		//printf("%d: %f, %f, %f\n", threadIdx.x, obj->translation[0], obj->translation[1], obj->zrotation);
	}
	memcpy(mask, initialMask, room->mskCount * sizeof(unsigned char));

	//all threads to do update masks
	for (int i = 0; i < room->objctNum; i++) {
		mRect2f rect = get_circulate_boundingbox(room, &objs[i].boundingBox);
		update_mask_by_boundingBox(backupMask, rect, room->rowCount / 2, room->colCount, threadIdx.x, nThreads);
		//debugMask[1000] = (unsigned char)1;
		if (!objs[i].isFixed) {
			draw_objMask_patch(room, &objs[i], 
								objMaskArray[i].objMask, objMaskArray[i].maskSize, 
								tmpSlot, threadIdx.x, nThreads);
			draw_patch_on_union_mask(mask, &objs[i], objMaskArray[i].objMask, 
									 room->rowCount / 2, room->colCount, threadIdx.x, nThreads);
		}
	}

	__syncthreads();

	sumUpMask(room, mask, tmpSlot, &wmaskArea[0], nThreads);

	sumUpMask(room, backupMask, tmpSlot, &wmaskArea[1], nThreads);
}

__device__
void getTemporalTransAndRot(sharedRoom * room, singleObj* objs, float * results, float cost) {
	float maxCost = results[0];
	int i = 1, maxPos = 0, singleSize = room->objctNum * 4 + 1;
	for (i = 1; i<MAX_KEPT_RES; i++) {
		if (maxCost == INFINITY)
			break;
		if (results[singleSize * i] >maxCost) {
			maxPos = i; maxCost = results[singleSize * i];
		}
	}
	//if (threadIdx.x == 0)
		//printf("cost :%f, pos: %d \n", cost, maxPos);
	if (cost < maxCost) {
		int baseId = singleSize * maxPos;
		results[baseId] = cost;
		for (int i = 0; i<room->objctNum; i++) {
			results[baseId + 4 * i + 1] = objs[i].translation[0];
			results[baseId + 4 * i + 2] = objs[i].translation[1];
			results[baseId + 4 * i + 3] = objs[i].translation[2];
			results[baseId + 4 * i + 4] = objs[i].zrotation;
			//if(threadIdx.x == 0)
			//printf("%f - %f - %f -%f \n", results[baseId + 4 * i + 1], results[baseId + 4 * i + 2], results[baseId + 4 * i + 3], results[baseId + 4 * i + 4]);
		}
	}
}

__device__
int randomly_perturb(sharedRoom* room, singleObj * objs, int pickedIdx,
	unsigned char*initialMask, unsigned char * mask, unsigned char* backupMask,
	float *wmaskArea, float* tmpSlot, objMaskWrapper* objMaskArray) {
	int secondChangeId = -1;
	singleObj * obj = &objs[pickedIdx];
	storeOrigin(obj);
	int index = blockIdx.x * nThreads + threadIdx.x;
	// REAL RANDOM HERE
	if (threadIdx.x == 0) {
		if (obj->adjoinWall)
			random_along_wall(room, obj);
		else {
			int trytimes = 0;
			int randomMethod = (room->objctNum < 2 || obj->alignedTheWall) ? 2 : 3;
			switch (get_int_random(randomMethod, index)) {
				// randomly rotate
			case 0:
				if (obj->alignedTheWall)
					set_obj_zrotation(obj, room->deviceWalls[get_int_random(room->wallNum, index)].zrotation);
				else
					set_obj_zrotation(obj, get_float_random(PI, index));
				break;
			case 1:
				while (set_obj_translation(room, obj,
					get_float_random(room->half_width, index),
					get_float_random(room->half_height, index), true));
				break;
			case 2:
				singleObj * obj2;

				// float tmpx = obj->translation[0], tmpy=obj->translation[1], tmprot = obj->zrotation;
				while (trytimes++ < 5) {
					obj2 = &objs[get_int_random(room->objctNum, index)];
					if (obj2->id == pickedIdx || obj2->adjoinWall || obj2->alignedTheWall)
						continue;
					storeOrigin(obj2);

					if (!set_obj_translation(room, obj, obj2->translation[0], obj2->translation[1]))
						continue;
					if (!set_obj_translation(room, obj2, obj->lastTransAndRot[0], obj->lastTransAndRot[1])) {
						set_obj_translation(room, obj, obj->lastTransAndRot[0], obj->lastTransAndRot[1]);
						continue;
					}
					break;
				}
				if (trytimes >= 5)
					while (set_obj_translation(room, obj,
						get_float_random(room->half_width, index),
						get_float_random(room->half_height, index), true));
				else {
					set_obj_zrotation(obj, obj2->zrotation);
					set_obj_zrotation(obj2, obj->lastTransAndRot[3]);
					secondChangeId = obj2->id;
				}
				break;
			default:
				break;
			}//end switch
		}// end not adjoint wall
	}//end thread == 0

	draw_objMask_patch(room, obj, objMaskArray[pickedIdx].objMask, objMaskArray[pickedIdx].maskSize, tmpSlot, threadIdx.x, nThreads);
	change_an_obj_backupMask(room, obj, backupMask, nThreads);
	if (secondChangeId != -1) {
		draw_objMask_patch(room, &objs[secondChangeId], objMaskArray[secondChangeId].objMask, objMaskArray[secondChangeId].maskSize, tmpSlot, threadIdx.x, nThreads);
		change_an_obj_backupMask(room, &objs[secondChangeId], backupMask, nThreads);
	}


	// memset(mask, 0, room->mskCount * sizeof(unsigned char));
	memcpy(mask, initialMask, room->mskCount * sizeof(unsigned char));
	for (int i = 0; i < room->freeObjNum; i++)
		draw_patch_on_union_mask(mask, &objs[room->freeObjIds[i]], objMaskArray[room->freeObjIds[i]].objMask, room->rowCount / 2, room->colCount, threadIdx.x, nThreads);

	__syncthreads();

	sumUpMask(room, mask, tmpSlot, &wmaskArea[0], nThreads);
	sumUpMask(room, backupMask, tmpSlot, &wmaskArea[1], nThreads);

	return secondChangeId;
}

__device__
void Metropolis_Hastings(float* costList, float* temparature, int*pickedupIds, 
						maskWrapper maskWrap, objMaskWrapper* objMaskArray) {
	float cpost, p0, p1, alpha;
	sharedRoom * room = sWrapper[0].wRoom;
	singleObj * objsBlock = &sWrapper[0].wObjs[blockIdx.x * room->objctNum];
	int startId = blockIdx.x * nThreads;
	int index = startId + threadIdx.x;
	int maskStart = room->mskCount * blockIdx.x;
	int secondChangeId, pickedId;

	initial_assignment(room, objsBlock,
		maskWrap.initialMask, &maskWrap.wMask[maskStart], &maskWrap.backMask[maskStart],
		&maskWrap.wmaskArea[2*blockIdx.x], &costList[startId], objMaskArray);
	//maskWrap.wmaskArea[2 * blockIdx.x] = 5000;
	//maskWrap.wmaskArea[2 * blockIdx.x + 1] = 5000;
	getWeightedCost(room, objsBlock, sWrapper[0].wPairRelation, &maskWrap.wmaskArea[2 * blockIdx.x], &costList[startId]);
	__syncthreads();

	float cpre = sumUp_weighted_dataInShare(&costList[startId + 1], weights, WEIGHT_NUM);
	getTemporalTransAndRot(room, objsBlock, sWrapper[0].resTransAndRot, cpre);
	
	if (blockIdx.x == 0 && threadIdx.x == 0)
		displayResult(costList, weights);
	if (sWrapper[0].nTimes == 0)
		return;
	for (int nt = 0; nt<sWrapper[0].nTimes; nt++) {
		if (threadIdx.x == 0) {
			if (nBlocks>1 && nt % 10 == 0)
				changeTemparature(temparature);
			p0 = density_function(temparature[blockIdx.x], cpre);
		}

		pickedId = pickedupIds[blockIdx.x];

		// if(threadIdx.x ==0)
		// printf("block: %d pickup: %d\n",blockIdx.x, pickedId );
		// fprintf( stderr,"threadIdx: %d, nTimes: %d\n", threadIdx.x, nt);
		//printf("threadIdx: %d, nTimes: %d\n", threadIdx.x, nt);
		__syncthreads();

		if (threadIdx.x == 0) {
			pickedupIds[blockIdx.x] = room->freeObjIds[get_int_random(room->freeObjNum)];
			// printf("block: %d pickup: %d\n",blockIdx.x, pickedId );
		}


		secondChangeId = randomly_perturb(room, objsBlock, pickedId,
						 maskWrap.initialMask, &maskWrap.wMask[maskStart], &maskWrap.backMask[maskStart],
						 &maskWrap.wmaskArea[2*blockIdx.x], &costList[startId],
						 objMaskArray);

		getWeightedCost(room, objsBlock, sWrapper[0].wPairRelation, &maskWrap.wmaskArea[2 * blockIdx.x], &costList[startId]);
		// if(threadIdx.x == 0 && nt%10==0 ){
		//     for(int i=0; i<2; i++)
		//         printf("obj: %d, loc: %f, %f\n",i, objsBlock[i].translation[0], objsBlock[i].translation[1] );
		// displayResult(costList, weights);
		// }

		__syncthreads();

		cpost = sumUp_weighted_dataInShare(&costList[startId + 1], weights, WEIGHT_NUM);

		costList[index] = 0;

		if (threadIdx.x == 0) {
			p1 = density_function(temparature[blockIdx.x], cpost);
			alpha = fminf(1.0f, p1 / p0);
			// printf("alpha: %f cpre: %f cpost: %f\n",alpha, cpre, cpost );
			if (alpha < THREADHOLD_T) {
				restoreOrigin(room, &maskWrap.wMask[maskStart], &costList[startId],
					&objsBlock[pickedId], nThreads);
				if (secondChangeId != -1)
					restoreOrigin(room, &maskWrap.wMask[maskStart], &costList[startId],
						&objsBlock[secondChangeId], nThreads);
			}
			else if (cpost < cpre) {
				getTemporalTransAndRot(room, objsBlock, sWrapper[0].resTransAndRot, cpost);
				cpre = cpost;
			}
		}//end thread 0
	}//end for
}
__device__
void Initialize_Room_In_Device(sharedRoom* room, singleObj* objs, objMaskWrapper* objMaskArray, unsigned char* initialMask, float*obsVertices, float*tmpSlot) {
	for (int k = 0; k<room->obstacleNum; k++) {
		float minx = obsVertices[0], maxx = obsVertices[0], miny = obsVertices[1], maxy = obsVertices[1];
		for (int i = 1; i<4; i++) {
			minx = (obsVertices[2 * i] < minx) ? obsVertices[2 * i] : minx;
			maxx = (obsVertices[2 * i] > maxx) ? obsVertices[2 * i] : maxx;
			miny = (obsVertices[2 * i + 1] < miny) ? obsVertices[2 * i + 1] : miny;
			maxy = (obsVertices[2 * i + 1] > maxy) ? obsVertices[2 * i + 1] : maxy;
		}
		mRect2f boundingBox = { minx, maxy, maxx - minx, maxy - miny };

		update_mask_by_object(initialMask, tmpSlot, &obsVertices[8 * k], boundingBox,
			room->rowCount / 2, room->colCount,
			threadIdx.x, nThreads);
	}
	__syncthreads();
	sumUpMask(room, initialMask, tmpSlot, &room->obstacleArea, nThreads);
	__syncthreads();

	for (int i = 0; i<room->objctNum; i++) {
		if (objs[i].isFixed) {
			draw_objMask_patch(room, &objs[i], objMaskArray[i].objMask, objMaskArray[i].maskSize, tmpSlot, threadIdx.x, nThreads);
			draw_patch_on_union_mask(initialMask, &objs[i], objMaskArray[i].objMask, room->rowCount / 2, room->colCount, threadIdx.x, nThreads);
		}
	}
}
__global__
void Do_Metropolis_Hastings(sharedWrapper *gWrapper, maskWrapper* maskWrap, objMaskWrapper* objMaskArray) {
	sWrapper[0] = *gWrapper;
	if (blockIdx.x == 0) {
		Initialize_Room_In_Device(sWrapper[0].wRoom, sWrapper[0].wObjs, objMaskArray, maskWrap[0].initialMask, sWrapper[0].obstacleVertices, sWrapper[0].wFloats);
	}
	else if(threadIdx.x < sWrapper[0].wRoom->objctNum){
			int objId = blockIdx.x * sWrapper[0].wRoom->objctNum + threadIdx.x;
			sWrapper[0].wObjs[objId] = sWrapper[0].wObjs[threadIdx.x];
			objMaskArray[blockIdx.x * sWrapper[0].wRoom->objctNum + threadIdx.x] = objMaskArray[threadIdx.x];
	}

	float* costList = sWrapper[0].wFloats;
	float* temparature = (float *)& costList[nBlocks * nThreads];
	int * pickedupIds = (int*)&temparature[nBlocks];

	temparature[blockIdx.x] = get_float_random(10) / 100;
	for (int i = threadIdx.x; i<gWrapper->nTimes; i += nThreads)
		pickedupIds[i] = sWrapper[0].wRoom->freeObjIds[get_int_random(sWrapper[0].wRoom->freeObjNum)];

	Metropolis_Hastings(costList, temparature, pickedupIds, maskWrap[0], &objMaskArray[blockIdx.x * sWrapper[0].wRoom->objctNum]);
	// if(blockIdx.x == 0)
	// printf("thread: %d, err: \n",threadIdx.x, cudaGetLastError());
	__syncthreads();

	if (threadIdx.x < sWrapper[0].wRoom->objctNum) {
		int singleSize = gWrapper->wRoom->objctNum * 4 + 1;
		for (int i = 0; i<MAX_KEPT_RES; i++) {
			gWrapper->resTransAndRot[singleSize * i] = sWrapper[0].resTransAndRot[singleSize * i];

			int startPos = singleSize * i + 4 * threadIdx.x;
			for (int k = 1; k<5; k++)
				gWrapper->resTransAndRot[startPos + k] = sWrapper[0].resTransAndRot[startPos + k];
		}
	}
	__syncthreads();
}
void copyShare(Room * hroom, sharedRoom * sroom) {
	cudaMemcpy(sroom->freeObjIds, hroom->freeObjIds, hroom->freeObjNum * sizeof(int), cudaMemcpyHostToDevice);
	cudaMemcpy(sroom->groupMap, hroom->groupMap, MAX_GROUP_ALLOW * sizeof(groupMapStruct), cudaMemcpyHostToDevice);
	cudaMemcpy(sroom->pairMap, hroom->pairMap, CONSTRAIN_PAIRS * sizeof(pairMapStruct), cudaMemcpyHostToDevice);
}
void generate_suggestions(Room * m_room, string & resString, int nTimes) {
	maskWrapper * gmaskWrapper;
	cudaMallocManaged(&gmaskWrapper, sizeof(maskWrapper));
	unsigned tMem = m_room->rowCount * m_room->colCount  * sizeof(unsigned char);
	cudaMallocManaged(&gmaskWrapper->initialMask, tMem);
	cudaMemset(gmaskWrapper->initialMask, 0, tMem);

	cudaMallocManaged(&gmaskWrapper->wMask, nBlocks *tMem);

	cudaMallocManaged(&gmaskWrapper->backMask, nBlocks *tMem);
	cudaMemset(gmaskWrapper->backMask, 0, nBlocks*tMem);

	unsigned maskAreaMem = 2 * nBlocks * sizeof(float);
	cudaMallocManaged(&gmaskWrapper->wmaskArea, maskAreaMem);
	cudaMemset(gmaskWrapper->wmaskArea, 0, maskAreaMem);

	//Init gWrapper
	sharedWrapper *gWrapper;
	cudaMallocManaged(&gWrapper, sizeof(sharedWrapper));
	gWrapper->nTimes = nTimes;
	cudaMallocManaged(&gWrapper->wRoom, sizeof(sharedRoom));
	m_room->CopyToSharedRoom(gWrapper->wRoom);
	copyShare(m_room, gWrapper->wRoom);

	unsigned objMem = nBlocks * m_room->objctNum * sizeof(singleObj);
	cudaMallocManaged(&gWrapper->wObjs, objMem);
	
	//patches masks
	objMaskWrapper * objMaskArray;
	cudaMallocManaged(&objMaskArray, nBlocks * m_room->objctNum * sizeof(objMaskWrapper));

	for (int i = 0; i<m_room->objctNum; i++) {
		gWrapper->wObjs[i] = m_room->objects[i];
		objMaskArray[i].maskSize = m_room->objects[i].maskLen* m_room->objects[i].maskLen * sizeof(unsigned char);
		cudaMallocManaged(&objMaskArray[i].objMask, objMaskArray[i].maskSize);

		cudaMemset(objMaskArray[i].objMask, 0, objMaskArray[i].maskSize);
	}

	if (m_room->obstacles.size() != 0) {
		int obstacleVerticesMem = sizeof(float) * 8 * m_room->obstacles.size();
		cudaMallocManaged(&gWrapper->obstacleVertices, obstacleVerticesMem);
		m_room->get_obstacle_vertices(gWrapper->obstacleVertices);
	}

	int floatMem = (nBlocks *(2 + nThreads)) * sizeof(float);
	cudaMallocManaged(&gWrapper->wFloats, floatMem);

	
	unsigned pairMem = 0;
	if (m_room->actualPairs.size()) {
		pairMem = m_room->actualPairs.size() * 4 * sizeof(int);
		cudaMallocManaged(&gWrapper->wPairRelation, pairMem);
		for (int i = 0; i<m_room->actualPairs.size(); i++) {
			for (int j = 0; j<4; j++)
				gWrapper->wPairRelation[4 * i + j] = m_room->actualPairs[i][j];
		}
	}
	
	unsigned resMem = (m_room->objctNum * 4 + 1) * MAX_KEPT_RES * sizeof(float);
	cudaMallocManaged(&gWrapper->resTransAndRot, resMem);

	unsigned totolMem = sizeof(sharedWrapper) + sizeof(sharedRoom)
		+ objMem  + floatMem + pairMem + resMem + nThreads * sizeof(float);

 	Do_Metropolis_Hastings<<<nBlocks, nThreads, totolMem>>>(gWrapper, gmaskWrapper, objMaskArray);


	cudaDeviceSynchronize();
	const char * errStr = cudaGetErrorString(cudaGetLastError());
	cout << "error:" << errStr << endl;

	display_suggestions(m_room, gWrapper->resTransAndRot);
	
	int resObjMem = (5*m_room->objctNum+1)*sizeof(float);//id, cate, width, height, zheight


	resString = std::to_string( m_room->objctNum ) ;
	for (int i = 0; i < m_room->objctNum; i++) {
		resString += " " + to_string(m_room->objects[i].id);
		resString += " " + to_string(m_room->objects[i].catalogId);
		resString += " " + to_string(m_room->objects[i].objWidth);
		resString += " " + to_string(m_room->objects[i].objHeight);
		resString += " " + to_string(m_room->objects[i].zheight);
	}
		
	int singleSize = 4 * m_room->objctNum + 1;
	for (int i = 0, startId = 0; i< MAX_KEPT_RES; i++, startId = i * singleSize) {
		cout << "result: " << i << "- cost: " << gWrapper->resTransAndRot[startId] << endl;

		for (int n = 0; n<m_room->objctNum; n++) {
			cout << "object: " << n << " pos and rot:";
			string res = "";
			for (int pi = 1; pi < 5; pi++)
				res += " " + to_string(gWrapper->resTransAndRot[startId + 4 * n + pi]);
			resString += res;
			cout << res << endl;
		}
	}
	cudaFree(gmaskWrapper->initialMask);
	cudaFree(gmaskWrapper->wMask);
	cudaFree(gmaskWrapper->backMask);
	cudaFree(gmaskWrapper->wMask);
	cudaFree(gmaskWrapper->wmaskArea);

	cudaFree(gWrapper->wRoom);
	cudaFree(gWrapper->wObjs);
	cudaFree(gWrapper->obstacleVertices);
	cudaFree(gWrapper->wFloats);
	cudaFree(gWrapper->wPairRelation);
	cudaFree(gWrapper->resTransAndRot);
}
void startToProcess(Room * m_room, string &resString, int nTimes) {
	if (m_room->objctNum == 0)
		return;
	setUpDevices();

	clock_t start, finish;
	float costtime;
	start = clock();
	generate_suggestions(m_room, resString, nTimes);

	finish = clock();
	costtime = (float)(finish - start) / CLOCKS_PER_SEC;
	cout << "Runtime: " << costtime << endl;
}

void Entrance(string rawString, string &resString) {
	Room* parserRoom = new Room();
	parser_customer_input_string(rawString, parserRoom, true);
	startToProcess(parserRoom, resString, 0);
}

