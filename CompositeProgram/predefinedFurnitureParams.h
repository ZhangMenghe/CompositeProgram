#pragma once
#include<iostream>
#include<map>
#include <string>
#include "Layouter/predefinedConstrains.h"
using namespace std;
void get_default_furniture_map(map<int, string>& furMap) {
	
	furMap[TYPE_CHAIR] = "40, 40, 70,";//
	furMap[TYPE_COFFETABLE] = "60, 40, 30,";
	furMap[TYPE_SOFA] = "150, 80, 60,";
	furMap[TYPE_ENDTABLE] = "30, 30, 50,";
	furMap[TYPE_BED] = "180, 200, 90,";//
	furMap[TYPE_NIGHTSTAND] = "50, 40, 50,";
	furMap[TYPE_SHELF] = "80, 40, 90,";
	furMap[TYPE_TABLE] = "120, 80, 80,";
	furMap[TYPE_DESK] = "100, 80, 60,";//
}
