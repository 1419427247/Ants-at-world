#[compute]
#version 450

// 每个工作组的调用次数 (x, y, z)
layout(local_size_x = 2, local_size_y = 1, local_size_z = 1) in;

// 绑定到脚本中创建的缓冲区
layout(set = 0, binding = 0, std430) restrict buffer MyDataBuffer {
    float data[];
} my_data_buffer;

// 每个调用执行的代码
void main() {
    // gl_GlobalInvocationID.x 在所有工作组中唯一标识此调用
    my_data_buffer.data[gl_GlobalInvocationID.x] *= 2.0;
}
