### GPU nodes

GPU users must subscribe to [EKS-optimized AMI with GPU Support](https://aws.amazon.com/marketplace/pp?sku=58kec53jbhfbaqpgzivdyhdo9).

EKS AMI does not expose `nvidia.com/gpu` properly, so scheduling with `--limits=nvidia.com/gpu=1` doesn't work either. Re-label nodes on `beta.kubernetes.io/instance-type`.

All GPUs on multi-core cards are mapped into all containers, so schedule conflicts should be resolved elsewhere.

Try:

```bash
kubectl run -ti --rm \
  --image=tensorflow/tensorflow:latest-gpu \
  --overrides='{ "apiVersion": "apps/v1beta1", "spec": { "template": { "spec": { "nodeSelector": { "beta.kubernetes.io/instance-type": "p2.xlarge" } } } } }' \
  tensorflow /bin/bash
```

Then `python -c 'import tensorflow as tf; tf.Session(config=tf.ConfigProto())'`.