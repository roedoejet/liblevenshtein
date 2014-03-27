fs = require 'fs'

seed_random = require 'seed-random'

{levenshtein: {distance}} = require '../../src/levenshtein/distance'
{levenshtein: {Transducer}} = require '../../src/levenshtein/transducer'
{levenshtein: {Builder}} = require '../../src/levenshtein/builder'
{levenshtein: {Dawg}} = require '../../src/collection/dawg'
{levenshtein: {truth_table}} = require '../../src/util/truth-table'
{levenshtein: {mutate}} = require '../../src/util/mutate'

{levenshtein: {operations}} = require '../../src/util/operations'
{insertion, deletion, substitution, transposition, merge, split} = operations

[dawg, lorem_ipsum] = do ->
  path = "#{__dirname}/../../../shared/resources/lorem-ipsum-terms.txt"
  lorem_ipsum = fs.readFileSync(path, 'utf8').split('\n')
  if lorem_ipsum[lorem_ipsum.length - 1] is ''
    lorem_ipsum.pop() #-> drop the empty string
  [new Dawg(lorem_ipsum), lorem_ipsum]

test_property = (property, valid, invalid) ->
  (test) ->
    for value in valid
      builder = @builder[property](value)
      test.ok builder instanceof Builder
      test.ok builder[property]() is value
    for value in invalid
      test.throws -> @builder.dictionary_sorted(value)
    test.done()

test_builder = (test, property_values, truths, builder=new Builder(), i=0) ->
  if i < property_values.length
    if truths[i]
      for [property, values] in property_values
        for value in values
          builder = new Builder(builder)
          builder[property](value)
          test_builder(test, property_values, truths, builder, 1+i)
    else
      test_builder(test, property_values, truths, builder, 1+i)
  else
    unless builder.transducer() instanceof Transducer
      params = (builder[property]() for [property, values] in property_values)
      test.ok fail,
        "Expected builder.transducer() to return an instance of Transducer for #{params}"

test_candidates = (test, terms, term, n, transducer, distance, algorithm) ->
  candidates = transducer.transduce(term, n)
  candidates_length = candidates.length
  while candidates.peek()
    [candidate, d] = candidates.pop()
    if d isnt distance(term, candidate)
      test.ok false,
        "For algorithm=#{algorithm}, expected transduced "+
        "distance(#{term},#{candidate}) = #{distance(term,candidate)}, "+
        "but was #{d}."
    if d > n
      test.ok false,
        "For algorithm=#{algorithm}, the transduced distance, #{d}, is "+
        "greater than the threshold, #{n}!"
      throw new Error("Bam!")
  num_candidates = 0
  num_candidates += distance(term, candidate) <= n for candidate in terms
  if candidates_length isnt num_candidates
    console.log ['distance', distance.toString()] #-> correct function?
    candidates = transducer.transduce(term, n)
    while candidates.peek()
      [candidate, d] = candidates.pop()
      console.log ['candidate', candidate, 'distance', d]
    for candidate in terms
      if distance(term, candidate) <= n
        console.log ['correct(candidate)', candidate, 'correct(distance)', distance(term, candidate)]
    test.ok false,
      "For algorithm=#{algorithm}, term=#{term}, expected the number of "+
      "transduced candidates to be #{num_candidates}, but was "+
      "#{candidates_length}"
    throw new Error("Bam!")

module.exports =
  'Property Tests':
    setUp: (callback) ->
      @builder = new Builder()
      callback()
    'dictionary should be readable and writable':
      test_property('dictionary', [['foo'], ['bar'], new Dawg(['foo'])], ['foo', null, `undefined`])
    'dictionary_sorted should be readable and writable':
      test_property('dictionary_sorted', [true, false], ['true', 1, 0, null])
    'algorithm should be readable and writable':
      test_property('algorithm', ['standard', 'transposition', 'merge_and_split'], ['foobar', null, `undefined`])
    'sort_matches should be readable and writable':
      test_property('sort_matches', [true, false], ['true', 1, 0, null])
    'case_insensitive_sort should be readable and writable':
      test_property('case_insensitive_sort', [true, false], ['true', 1, 0, null])
    'include_distance should be readable and writable':
      test_property('include_distance', [true, false], ['true', 1, 0, null])
  'Builder#transducer should return an instance of Transducer for every combination of options': (test) ->
    property_values = [
      ['dictionary', [[], lorem_ipsum, dawg]]
      ['dictionary_sorted', [true, false]]
      ['algorithm', ['standard', 'transposition', 'merge_and_split']]
      ['sort_matches', [true, false]]
      ['case_insensitive_sort', [true, false]]
      ['include_distance', [true, false]]
    ]
    for truths in truth_table(property_values.length)
      test_builder(test, property_values, truths)
    test.done()
  'Verify there are only true-positives and true-negatives': (test) ->
    random = seed_random(0xDEADBEEF)

    alphabet = do ->
      alphabet = []
      alphabet.push String.fromCharCode(c) for c in [32..128] #-> No Ctrl-chars
      alphabet.join('')

    # The probabilities will be normalized
    mutations = [
      [1.0, (term) -> insertion(term, alphabet, random)]
      [1.0, (term) -> deletion(term, alphabet, random)]
      [1.0, (term) -> substitution(term, alphabet, random)]
      [1.0, (term) -> transposition(term, alphabet, random)]
      [1.0, (term) -> merge(term, alphabet, random)]
      [1.0, (term) -> split(term, alphabet, random)]
    ]

    builder = new Builder().dictionary(dawg).sort_matches(false)
    transducers =
      standard: [
        builder.algorithm('standard').transducer()
        distance('standard')
      ]
      transposition: [
        builder.algorithm('transposition').transducer()
        distance('transposition')
      ]
      merge_and_split: [
        builder.algorithm('merge_and_split').transducer()
        distance('merge_and_split')
      ]

    do (; distance) -> #-> avoids symbol-table conflict with distance-constructor
      for own algorithm, [transducer, distance] of transducers
        for n in [0..5] #-> maximum edit distance
          for term in lorem_ipsum
            test_candidates(test, lorem_ipsum, term, n, transducer, distance, algorithm)
            for i in [1..3] #-> number of times to mutate the term
              mutation = mutate(mutations, term.length, random, term)
              test_candidates(test, lorem_ipsum, mutation, n, transducer, distance, algorithm)
    test.done()
