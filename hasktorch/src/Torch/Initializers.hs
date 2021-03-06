module Torch.Initializers where

import Torch.Functional hiding (sqrt)
import Torch.Tensor
import Torch.TensorFactories

-- Note: Identity = linear w/o activation
data NonLinearity = Identity | Sigmoid | Tanh | Relu | LeakyRelu Float

data FanMode = FanIn | FanOut

newtype Shape = Shape [Int]

-- | Gain scaling value for He initialization
calculateGain :: NonLinearity -> Float
calculateGain Identity = 1.0
calculateGain Sigmoid = 1.0
calculateGain Tanh = 5.0 / 3
calculateGain Relu = sqrt 2.0
calculateGain (LeakyRelu param) = sqrt (2.0 / (1.0 + (param) ^^ 2))

-- | Fan-in / Fan-out scaling calculation
calculateFan :: [Int] -> (Int, Int)
calculateFan shape =
    if dimT < 2 then
        error "Fan in and fan out can not be computed for tensor with fewer than 2 dimensions"
    else if dimT == 2 then
        (shape !! 1, shape !! 0)
        else 
            (numInputFmaps * receptiveFieldSize,
            numOutputFmaps * receptiveFieldSize)
    where
        dimT = length shape
        numInputFmaps = shape !! 1 -- size t 1
        numOutputFmaps = shape !! 0 -- size t 0
        receptiveFieldSize = product $ tail shape

-- | Xavier Initialization - Uniform
xavierUniform :: Float -> [Int] -> IO Tensor
xavierUniform gain shape = do
    init <- rand' shape
    pure $ subScalar (mulScalar init (bound * 2.0)) bound
    where
        (fanIn, fanOut) = calculateFan shape
        std = gain * sqrt (2.0 / (fromIntegral fanIn + fromIntegral fanOut))
        bound = sqrt 3.0 * std

-- | Xavier Initialization - Normal
xavierNormal :: Float -> [Int] -> IO Tensor
xavierNormal gain shape = do
    init <- randn' shape
    pure $ mulScalar init std
    where
        (fanIn, fanOut) = calculateFan shape
        std = gain * sqrt (2.0 / (fromIntegral fanIn + fromIntegral fanOut))

-- | Get fan in or fan out value depending on selected fan mode, used by Kaiming
getter :: FanMode -> ((Int, Int) -> Int)
getter FanIn = fst
getter FanOut = snd

-- | Kaiming Initialization - Uniform
kaimingUniform :: FanMode -> NonLinearity -> [Int] -> IO Tensor
kaimingUniform mode nonlinearity shape = do
    init <- rand' shape
    pure $ subScalar (mulScalar init (bound * 2.0)) bound
    where 
        gain = calculateGain nonlinearity
        fanValue = fromIntegral $ (getter mode) (calculateFan shape)
        std = gain / (sqrt fanValue)
        bound = (sqrt 3.0) * std

-- | Kaiming Initialization - Normal
kaimingNormal :: FanMode -> NonLinearity -> [Int] -> IO Tensor
kaimingNormal mode nonlinearity shape = do
    init <- (randn' shape)
    pure $ mulScalar init std
    where 
        gain = calculateGain nonlinearity
        fanValue = fromIntegral $ (getter mode) (calculateFan shape)
        std = gain / (sqrt fanValue)

-- | Handle weights + bias
-- based on https://github.com/pytorch/pytorch/blob/master/torch/nn/modules/linear.py#L79
kaimingFC :: [Int] -> IO (Tensor, Tensor)
kaimingFC weightShape = do
    weight <- kaimingUniform' weightShape
    biasInit <- rand' biasShape
    let bias = subScalar (mulScalar biasInit (bound * 2.0)) bound
    pure (weight, bias)
    where
        (fanIn, _) = calculateFan weightShape
        bound = 1.0 / (sqrt . fromIntegral $ fanIn) :: Float
        biasShape = [weightShape !! 0]

{- PyTorch defaults -}

kaimingUniform' :: [Int] -> IO Tensor
kaimingUniform' = kaimingUniform FanIn (LeakyRelu 0.0)

kaimingNormal' :: [Int] -> IO Tensor
kaimingNormal' = kaimingNormal FanIn (LeakyRelu 0.0)

xavierUniform' :: [Int] -> IO Tensor
xavierUniform' = xavierUniform 1.0

xavierNormal' :: [Int] -> IO Tensor
xavierNormal' = xavierNormal 1.0
