require 'statsample'

total_clicks = 0
total_impressions = 0

ads = {}
advertisers = {}
keywords = {}
queries = {}

def log(msg)
  warn("#{Time.now}: #{msg}")
end

log("Loading keywords...")
keywords_file = File.new("purchasedkeywordid_tokensid.txt", "r")
while (line = keywords_file.gets)
  elements = line.split("\t")

  keyword_id = elements[0]
  keyword_tokens = elements[1].split("|")
  keywords[keyword_id] = keyword_tokens
end
keywords_file.close
log("OK")

log("Loading queries...")
queries_file = File.new("queryid_tokensid.txt.10000", "r")
while (line = queries_file.gets)
  elements = line.split("\t")

  query_id = elements[0]
  query_tokens = elements[1].split("|")
  queries[query_id] = query_tokens
end
queries_file.close
log("OK")

log("Loading training data...")
training_file = File.new("training.txt.10000", "r")
while (line = training_file.gets)
  elements = line.split("\t")

  clicks = elements[0].to_i
  impressions = elements[1].to_i
  display_url = elements[2]
  ad_id = elements[3]
  advertiser_id = elements[4]
  depth = elements[5]
  position = elements[6]
  query_id = elements[7]
  keyword_id = elements[8]
  title_id = elements[9]
  description_id = elements[10]
  user_id = elements[11]

  ad = ads[ad_id]
  if ad.nil?
    ad = {}
    ad['clicks'] = clicks
    ad['impressions'] = impressions
    ads[ad_id] = ad
  else
    ad['clicks'] += clicks
    ad['impressions'] += impressions
  end

  advertiser = advertisers[advertiser_id]
  if advertiser.nil?
    advertiser = {}
    advertiser['clicks'] = clicks
    advertiser['impressions'] = impressions
    advertisers[advertiser_id] = advertiser
  else
    advertiser['clicks'] += clicks
    advertiser['impressions'] += impressions
  end

  total_clicks += clicks
  total_impressions += impressions
end
training_file.close
log("OK")

mean_ctr = total_clicks/total_impressions.to_f

ads.each_pair do |ad_id, ad|
  ad['pctr'] = ad['clicks']/ad['impressions'].to_f
end

advertisers.each_pair do |advertiser_id, advertiser|
  advertiser['pctr'] = advertiser['clicks']/advertiser['impressions'].to_f
end

observed_ctrs = []
ad_pctrs = []
advertiser_pctrs = []
keyword_match_vals = []

log("Building regression vectors...")
training_file = File.new("training.txt.10000", "r")
while (line = training_file.gets)
  elements = line.split("\t")

  clicks = elements[0].to_i
  impressions = elements[1].to_i
  display_url = elements[2]
  ad_id = elements[3]
  advertiser_id = elements[4]
  depth = elements[5]
  position = elements[6]
  query_id = elements[7]
  keyword_id = elements[8]
  title_id = elements[9]
  description_id = elements[10]
  user_id = elements[11]

  observed_ctrs.push(clicks / impressions.to_f)

  ad = ads[ad_id]
  ad_pctr = ad['pctr'] || mean_ctr
  ad_pctrs.push(ad_pctr)

  advertiser = advertisers[advertiser_id]
  advertiser_pctr = advertiser['pctr'] || mean_ctr
  advertiser_pctrs.push(advertiser_pctr)

  keyword_tokens = keywords[keyword_id] || []
  query_tokens = queries[query_id] || []
  keyword_matches = (keyword_tokens & query_tokens).length
  keyword_match_val = keyword_matches / [keyword_tokens.length, 3].min.to_f
  keyword_match_vals.push(keyword_match_val)
end
training_file.close
log("OK")

log("Calculating regression coefficients...")
ds = {"observed_ctr" => observed_ctrs.to_scale,
      "ad_pctr" => ad_pctrs.to_scale,
      "advertiser_pctr" => advertiser_pctrs.to_scale,
      "keyword_match_val" => keyword_match_vals.to_scale}.to_dataset
regression = Statsample::Regression.multiple(ds, "observed_ctr")
log(regression.summary)
log("OK")

constant = regression.constant
ad_pctr_coef = regression.coeffs["ad_pctr"]
advertiser_pctr_coef= regression.coeffs["advertiser_pctr"]
keyword_match_val_coef = regression.coeffs["keyword_match_val"]

# log("Constant: #{constant}")
# log("ad_pctr_coef: #{ad_pctr_coef}")
# log("advertiser_pctr_coef: #{advertiser_pctr_coef}")
# log("keyword_match_val_coef: #{keyword_match_val_coef}")

submission_file = File.new("submission.txt.10000", "w")
log("Calculating pctrs...")
test_file = File.new("test.txt.10000", "r")
while (line = test_file.gets)
  elements = line.split("\t")

  display_url = elements[0]
  ad_id = elements[1]
  advertiser_id = elements[2]
  depth = elements[3]
  position = elements[4]
  query_id = elements[5]
  keyword_id = elements[6]
  title_id = elements[7]
  description_id = elements[8]
  user_id = elements[9]

  ad = ads[ad_id] || {}
  ad_pctr = ad['pctr'] || mean_ctr
  # log("Ad pctr: #{ad_pctr}")

  advertiser = advertisers[advertiser_id] || {}
  advertiser_pctr = advertiser['pctr'] || mean_ctr
  # log("Advertiser pctr: #{advertiser_pctr}")

  keyword_tokens = keywords[keyword_id] || []
  query_tokens = queries[query_id] || []
  keyword_matches = (keyword_tokens & query_tokens).length
  keyword_match_val = keyword_matches / [keyword_tokens.length, 3].min.to_f
  # log("Keyword match val: #{keyword_match_val}")

  pctr = constant + (ad_pctr_coef * ad_pctr) + (advertiser_pctr_coef * advertiser_pctr) + (keyword_match_val_coef * keyword_match_val)
  # log("Pctr: #{pctr}")
  submission_file.puts(pctr)
end
test_file.close
submission_file.close
log("OK")

