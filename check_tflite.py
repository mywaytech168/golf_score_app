import sys

try:
    from tflite_runtime.interpreter import Interpreter
    print('Using tflite_runtime')
except ImportError:
    try:
        import tensorflow as tf
        Interpreter = tf.lite.Interpreter
        print('Using tensorflow ' + tf.__version__)
    except ImportError:
        print('ERROR: Neither tflite_runtime nor tensorflow installed')
        sys.exit(1)

interp = Interpreter(model_path='assets/models/golfballyolov8n_int8.tflite')
interp.allocate_tensors()

inputs = interp.get_input_details()
outputs = interp.get_output_details()

print('Input tensors: ' + str(len(inputs)))
for t in inputs:
    print('  [' + str(t['index']) + '] name=' + t['name'] + ' shape=' + str(t['shape'].tolist()) + ' dtype=' + str(t['dtype']) + ' quant=' + str(t['quantization']))

print('Output tensors: ' + str(len(outputs)))
for t in outputs:
    print('  [' + str(t['index']) + '] output_idx=' + str(outputs.index(t)) + ' name=' + t['name'] + ' shape=' + str(t['shape'].tolist()) + ' dtype=' + str(t['dtype']) + ' quant=' + str(t['quantization']))
