### GPU nodes

1. Hub component amends worker node's Ignition config to run `nvidia.service` to insert Nvidia driver kernel modules via [custom](https://github.com/agilestacks/agilestacks-components/tree/master/cuda/driver) [agilestacks/coreos-nvidia:{coreos-version}](https://hub.docker.com/r/agilestacks/coreos-nvidia/tags/) (based on [srcd/coreos-nvidia]( https://hub.docker.com/r/srcd/coreos-nvidia/tags/)). Currently the only version built is `1800.6.0 `.
2. Optionally, `kubectl label node NAME gpu=tesla|whatever`.
3. `kubectl apply -f nvidia-gpu-device-plugin.yml` to schedule [GKE's Nvidia](https://github.com/GoogleCloudPlatform/container-engine-accelerators/tree/master/cmd/nvidia_gpu) [Device Plugin](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/) to `gpu=` nodes or well-known instance types via `beta.kubernetes.io/instance-type=p2/p3/g3.*`.
4. `nvidia.service` copy OpenGL libraries to host `/nvidia`. Unfortunatelly, device plugin cannot mount the volume provided by `nvidia.service` container (/opt/nvidia) directly - there is no such capability in Kubernetes / device plugin v1beta1 API, see [AllocateResponse.Mounts](https://github.com/kubernetes/kubernetes/blob/master/pkg/kubelet/apis/deviceplugin/v1beta1/api.proto#L139).
```
source /etc/os-release
docker run -v /nvidia:/nvidia agilestacks/coreos-nvidia:$VERSION cp -rpd /opt/nvidia /
```
5. Test `kubectl run -ti --rm --limits=nvidia.com/gpu=1 --image=tensorflow/tensorflow:latest-gpu tensorflow /bin/bash`. Must use [limits](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/). Then `python -c 'import tensorflow as tf; tf.Session(config=tf.ConfigProto())'`.

The NVCC default link profile is to link statically to CUDA `--cudart=static`. Most people will be using Tensorflow / etc. derived images, so we don't need to bring full set of shared CUDA libraries into the container, just the OpenGL / OpenCL and `libcuda.so.1` parts. We need to research (or define) dev workflow, at least for our data-science / ML sample template.