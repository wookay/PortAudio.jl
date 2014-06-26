using Base.Test
using AudioIO
import AudioIO.AudioSample
import AudioIO.AudioBuf
import AudioIO.AudioRenderer
import AudioIO.AudioNode
import AudioIO.DeviceInfo
import AudioIO.render

# A TestNode just renders out 1:buf_size each frame
type TestRenderer <: AudioRenderer end

typealias TestNode AudioNode{TestRenderer}
TestNode() = TestNode(TestRenderer())

function render(node::TestRenderer,
                device_input::AudioBuf,
                info::DeviceInfo)
    return AudioSample[1:info.buf_size]
end

test_info = DeviceInfo(44100, 512)
dev_input = zeros(AudioSample, test_info.buf_size)

#### AudioMixer Tests ####

# TODO: there should be a setup/teardown mechanism and some way to isolate
# tests

info("Testing AudioMixer...")
mix = AudioMixer()
render_output = render(mix, dev_input, test_info)
@test render_output == AudioSample[]

testnode = TestNode()
mix = AudioMixer([testnode])
render_output = render(mix, dev_input, test_info)
@test render_output == AudioSample[1:test_info.buf_size]

test1 = TestNode()
test2 = TestNode()
mix = AudioMixer([test1, test2])
render_output = render(mix, dev_input, test_info)
# make sure the two inputs are being added together
@test render_output == 2 * AudioSample[1:test_info.buf_size]

# now we'll stop one of the inputs and make sure it gets removed
stop(test1)
render_output = render(mix, dev_input, test_info)
# make sure the two inputs are being added together
@test render_output == AudioSample[1:test_info.buf_size]

stop(mix)
render_output = render(mix, dev_input, test_info)
@test render_output == AudioSample[]

# TODO: I think we can do better than this
const FLOAT_THRESH = 1e-9

info("Testing SinOSC...")
freq = 440
# note that this range includes the end, which is why there are sample_rate+1 samples
t = linspace(0, 1, test_info.sample_rate+1)
test_vect = convert(AudioBuf, sin(2pi * t * freq))
osc = SinOsc(freq)
render_output = render(osc, dev_input, test_info)
@test mse(render_output, test_vect[1:test_info.buf_size]) < FLOAT_THRESH
render_output = render(osc, dev_input, test_info)
@test mse(render_output,
        test_vect[test_info.buf_size+1:2*test_info.buf_size]) < FLOAT_THRESH
@test 200 > (@allocated render(osc, dev_input, test_info))
stop(osc)
render_output = render(osc, dev_input, test_info)
@test render_output == AudioSample[]

info("Testing SinOsc with  signal input")
t = linspace(0, 1, test_info.sample_rate+1)
f = 440 .- t .* (440-110)
dt = 1 / test_info.sample_rate
# NOTE - this treats the phase as constant at each sample, which isn't strictly
# true. Unfortunately doing this correctly requires knowing more about the
# modulating signal and doing the real integral
phase = cumsum(2pi * dt .* f)
unshift!(phase, 0)
expected = convert(AudioBuf, sin(phase))

freq = LinRamp(440, 110, 1)
osc = SinOsc(freq)
render_output = render(osc, dev_input, test_info)
@test mse(render_output, expected[1:test_info.buf_size]) < FLOAT_THRESH
render_output = render(osc, dev_input, test_info)
@test mse(render_output,
        expected[test_info.buf_size+1:2*test_info.buf_size]) < FLOAT_THRESH
#@test 400 > (@allocated render(osc, dev_input, test_info))

info("Testing ArrayPlayer...")
v = rand(AudioSample, 44100)
player = ArrayPlayer(v)
render_output = render(player, dev_input, test_info)
@test render_output == v[1:test_info.buf_size]
render_output = render(player, dev_input, test_info)
@test render_output == v[(test_info.buf_size + 1) : (2*test_info.buf_size)]
stop(player)
render_output = render(player, dev_input, test_info)
@test render_output == AudioSample[]

# give a vector just a bit larger than 1 buffer size
v = rand(AudioSample, test_info.buf_size + 1)
player = ArrayPlayer(v)
render(player, dev_input, test_info)
render_output = render(player, dev_input, test_info)
@test render_output == v[test_info.buf_size+1:end]

info("Testing Gain...")

gained = TestNode() * 0.75
render_output = render(gained, dev_input, test_info)
@test render_output == 0.75 * AudioSample[1:test_info.buf_size]

info("Testing LinRamp...")
ramp = LinRamp(0.25, 0.80, 1)
expected = convert(AudioBuf, linspace(0.25, 0.80, test_info.sample_rate+1))
render_output = render(ramp, dev_input, test_info)
@test mse(render_output, expected[1:test_info.buf_size]) < 1e-16
render_output = render(ramp, dev_input, test_info)
@test mse(render_output, expected[(test_info.buf_size+1):(2*test_info.buf_size)]) < 1e-14
